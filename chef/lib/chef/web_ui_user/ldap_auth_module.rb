#
# Author:: Richard Nicholas (<richard.nicholas@betfair.com>)
# Copyright:: Copyright (c) 2010 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#


require "net/ldap"
require "chef/config"
require "chef/couchdb"
require "chef/web_ui_user/cdb_auth_module"

class Chef
  class WebUIUser
    class LDAPUser

      attr_accessor :user

      def initialize(opts = {})
        @user = opts['user']
        @group_membership_attribute = ( opts['group_membership_attribute'] ||= Chef::Config[:ldap_group_attribute]).to_sym
        @admin_groups = opts['admin_groups'] ||= Chef::Config[:ldap_chef_admin_groups]
        @user_groups = opts['user_groups'] ||= Chef::Config[:ldap_chef_user_groups]
      end

      def self.load(results)
        if !results
          nil
        elsif results.size == 0
          nil
        elsif results.size != 1
          raise ArgumentError, "Tried to bind user to multiple entries."
        else
          LDAPUser.new('user' => results.first,
                       'group_membership_attribute' => @group_membership_attribute,
                       'admin_groups' => @admin_groups,
                       'user_groups' => @user_groups )
        end
      end

      def member_of_group(group_name_list)
        if group_name_list.kind_of?(Array)
          group_name_list.any?{ |g| member_of_group(g) }
        else
          [@user[@group_membership_attribute.to_s]].flatten.include?(group_name_list)
        end
      end

      def is_admin?
        member_of_group(@admin_groups)
      end

      def is_user?
        member_of_group(@user_groups) || is_admin?
      end
      
    end #LDAPUser

    class LDAPConnection

      # Create a new LDAP connection
      def initialize(opts = {})
        @port = opts['port'] ||= Chef::Config[:ldap_port].to_i
        @hosts = [(opts['hosts'] ||= Chef::Config[:ldap_hosts])].flatten
        @method = Chef::Config[:ldap_encryption] ? :simple_tls : nil
        @method = ( opts['encrypt'] ? :simple_tls : nil ) if opts.has_key?('encrypt')
        @username = opts['username'] ||= Chef::Config[:ldap_bind_user]
        @password = opts['password'] ||= Chef::Config[:ldap_initial_bind_password]
        @auth = { :method => :simple, :username => @username, :password => @password }
        @base = opts['base'] ||= Chef::Config[:ldap_base_root_initial_bind] ||= Chef::Config[:ldap_base_root].dup
        @conn = Net::LDAP.new( :base => @base, :host => @hosts.first, :port => @port, :auth => @auth, :encryption => @method )
      end

      # Bind to the LDAP connection, with fallback on failure to alternative hosts
      def bind
        # Turn hosts into an array if it isn't one
        [@hosts].flatten.any? do |h|
          @conn.host = h
          @conn.bind
        end
      end

      # Bind with credentials given to a specified search path, search_root can be a Proc, which is called with name as the parameter
      # to allow for the username to be pre-processed to allow e.g for names to be input in the Active Directory domain\userid style
      #
      # User_field can also be a Proc and this is called with the given username to allow for more complex filter operations
      def bind_as(username, password, search_root = Chef::Config[:ldap_base_root],
                                      user_attribute = Chef::Config[:ldap_user_attribute],
                                      user_preprocess = Chef::Config[:ldap_user_preprocess])
        if bind
          search_root = LDAPConnection.call_if_proc(search_root, username)
          actual_username = LDAPConnection.call_if_proc(user_preprocess, username, username)
          search_filter = LDAPConnection.call_if_proc(user_attribute, actual_username, "(#{user_attribute}=#{LDAPConnection.ldap_escape(actual_username)})")
          Chef::WebUIUser::LDAPUser.load(@conn.bind_as(:base => search_root,  :password => password, :filter => search_filter))
        else
          raise ArgumentError, "Unable to bind to any LDAP server"        
        end
      end

      # Performs an LDAP search for the username.
      def ldap_search_for(username, search_root = Chef::Config[:ldap_base_root],
                                    user_attribute = Chef::Config[:ldap_user_attribute],
                                    user_preprocess = Chef::Config[:ldap_user_preprocess])
        if bind
          search_root = LDAPConnection.call_if_proc(search_root, username)
          actual_username = LDAPConnection.call_if_proc(user_preprocess, username, username)
          search_filter = LDAPConnection.call_if_proc(user_attribute, actual_username, "(#{user_attribute}=#{LDAPConnection.ldap_escape(actual_username)})")          
          Chef::WebUIUser::LDAPUser.load(@conn.search(:filter => search_filter, :base => search_root))
        else
          raise ArgumentError, "Unable to bind to any LDAP server"
        end
      end

      # Escapes the string so that it safe for use in LDAP search operations
      def self.ldap_escape(cn)
        cn.gsub(/[*()\\\00\/]/) { |c| "\\#{c.unpack('H*')[0]}" }
      end

      private

      # If "thing" is a proc, return the result of calling it now with the given parameter
      # If "thing" is something else return the given parameter, or the third parameter if present
      def self.call_if_proc(thing, param, return_if_not_proc = thing )
        thing.kind_of?(Proc) ? thing.call(param) : return_if_not_proc
      end

    end
    
    module LDAPAuthModule

      include Chef::WebUIUser::CDBAuthModule
      
      def self.included(base)
        base.extend Chef::WebUIUser::LDAPAuthModuleClassMethods
      end

      # (Don't!) Set the password for this object.  In normal use this shouldn't be called as errors are caught elsewhere with
      # the REST interface.
      def cdb_set_password(password,confirm_password=password)
        raise ArgumentError, "Passwords are controlled by the LDAP provider" if password || password != ""
      end

      # Verify the password for this object
      def cdb_verify_password(given_password)
        begin
          ldap_conn = Chef::WebUIUser::LDAPConnection.new
          auth_user = ldap_conn.bind_as(@name,given_password)
        rescue
          raise ArgumentError, "#{ldap_conn.get_operation_result.message} #{ldap_conn.get_operation_result.code}"
        end
        auth_user.is_user?
      end 

      # Save updates to the user providing that they do not clash with LDAP settings       
      def cdb_save
        raise_error_if_present :new_password, :confirm_new_password
        ldap_conn = Chef::WebUIUser::LDAPConnection.new
        ldap_user = ldap_conn.ldap_search_for(name)
        if ldap_user && ldap_user.is_user?
          admin = ldap_user.is_admin?
          results = couchdb.store("webui_user", name, self)
          @couchdb_rev = results["rev"]
          results
        else
          raise ArgumentError, "Cannot save as Chef user not found in LDAP"
        end
      end
      
      def instance_auth_module_name
        "LDAPAuthModule"
      end

    end

    module LDAPAuthModuleClassMethods

      include Chef::WebUIUser::CDBAuthModuleClassMethods

      def auth_module_name
        'LDAPAuthModuleClassMethods'
      end

      # Load an WebUIUser by name from LDAP.  If the user is not in LDAP and is in couchDB, get it from there.
      # We have to do this so that old (deleted from LDAP) users can be deleted from couchdb.
      def cdb_load(name)
        ldap_conn = Chef::WebUIUser::LDAPConnection.new
        ldap_user = ldap_conn.ldap_search_for(name)
        begin
          u = super(name)
        rescue Chef::Exceptions::CouchDBNotFound => e
          # If the user exists in LDAP and not in couchdb, store a basic new user in couchdb
          if ldap_user && ldap_user.is_user?
            u = Chef::WebUIUser.new('name' => name )
            u.admin = ldap_user.is_admin? 
            u.cdb_save
          else
            raise Chef::Exceptions::CouchDBNotFound,"User not found in LDAP or CouchDB"
          end          
        end
        # override admin setting with setting from LDAP if present
        u.admin = ldap_user.is_admin? if ldap_user
        u
      end
    end

  end
end

