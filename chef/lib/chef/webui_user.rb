#
# Author:: Adam Jacob (<adam@opscode.com>)
# Author:: Nuo Yan (<nuo@opscode.com>)
# Copyright:: Copyright (c) 2008 Opscode, Inc.
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
#if Chef::Config && Chef::Config.class == Module
  # Whoops.. Chef::Config is pointing at the Config Module used by rbconfig!
  # This seems to happen when called via Knife.  Reload config to fix the problem
#  load 'chef/config.rb'
#else
  require 'chef/config'
#end

require 'chef/mixin/params_validate'
require 'chef/index_queue'
require 'digest/sha1'
require 'json'
require 'uri'

Dir[File.join(File.dirname(__FILE__), 'web_ui_user', '*.rb')].sort.each { |lib| require lib }

class Chef
  class WebUIUser
    
    attr_accessor :validated, :admin, :name, :openid
    attr_reader   :password, :salt, :couchdb_id, :couchdb_rev, :authentication_status, :ui_suppressed_fields
    attr_accessor :new_password, :confirm_new_password
    
    include Chef::Mixin::ParamsValidate
    include Chef::IndexQueue::Indexable
    
   
    def self.select_authentication_module(auth_module_proc=Chef::Config[:web_ui_authentication_module])
      self.send(:include,auth_module_proc.call)
    end
  
    # Create a new Chef::WebUIUser object.
    def initialize(opts={})
      @name, @salt, @password = opts['name'], opts['salt'], opts['password']
      @new_password, @confirm_new_password = opts['new_password'], opts['confirm_new_password']
      @openid, @couchdb_rev, @couchdb_id = opts['openid'], opts['_rev'], opts['_id']
      @admin = false
    end
   
    def admin?
      admin
    end

    def verify_password(given_password)
      r = Chef::REST.new(Chef::Config[:chef_server_url])
      r.post_rest("users/#{URI.escape(name,URI::REGEXP::PATTERN::RESERVED)}/authentication",{ :given_password => given_password })["authenticated"]
    end
    
    # Transform the node to a Hash
    def to_hash
      # TODO: DRY this and to_json up!
      result = {
        'name' => name,
        'salt' => salt,
        'password' => password,
        'openid' => openid,
        'admin' => admin,
        'chef_type' => 'webui_user'
      }
      result["_id"]  = @couchdb_id if @couchdb_id  
      result["_rev"] = @couchdb_rev if @couchdb_rev
      result["new_password"] = @new_password if @new_password
      result["confirm_new_password"] = @confirm_new_password if @confirm_new_password
      result
    end    

    # Serialize this object as a hash 
    def to_json(*a)
      attributes = Hash.new
      recipes = Array.new
      result = {
        'name' => name,
        'json_class' => self.class.name,
        'salt' => salt,
        'password' => password,
        'openid' => openid,
        'admin' => admin,
        'chef_type' => 'webui_user',
      }
      result["_id"]  = @couchdb_id if @couchdb_id  
      result["_rev"] = @couchdb_rev if @couchdb_rev
      result["new_password"] = @new_password if @new_password
      result["confirm_new_password"] = @confirm_new_password if @confirm_new_password
      result.to_json(*a)
    end
    
    # Create a Chef::WebUIUser from JSON
    def self.json_create(o)
      me = new(o)
      me.admin = o["admin"]
      me
    end
  
    def self.list(inflate=false)
      r = Chef::REST.new(Chef::Config[:chef_server_url])
      if inflate
        response = Hash.new
        Chef::Search::Query.new.search(:user) do |n|
          response[n.name] = n unless n.nil?
        end
        response
      else
        r.get_rest("users")
      end
    end
    
    # Load a User by name
    def self.load(name)
        r = Chef::REST.new(Chef::Config[:chef_server_url])
        r.get_rest("users/#{URI.escape(name,URI::REGEXP::PATTERN::RESERVED)}")
    end
    
    # Remove this WebUIUser via the REST API
    def destroy
      r = Chef::REST.new(Chef::Config[:chef_server_url])
      r.delete_rest("users/#{URI.escape(name,URI::REGEXP::PATTERN::RESERVED)}")
    end
    
    # Save this WebUIUser via the REST API
    def save
      r = Chef::REST.new(Chef::Config[:chef_server_url])
      begin
        r.put_rest("users/#{URI.escape(name,URI::REGEXP::PATTERN::RESERVED)}", self)
      rescue Net::HTTPServerException => e
        if e.response.code == "404"
          r.post_rest("users", self)
        else
          raise e
        end
      end
      self
    end
    
    # Create the WebUIUser via the REST API
    def create
      r = Chef::REST.new(Chef::Config[:chef_server_url])
      r.post_rest("users", self)
      self
    end

    def self.admin_exist
      self.list.any?{ |u,url| self.load(u).admin? }
    end
    
    def escaped_name
      URI.escape(name, URI::REGEXP::PATTERN::RESERVED)
    end



    def raise_error_if_present(*args)
      args.each do |arg|
        raise ArgumentError, "#{arg} cannot be set with the #{self.instance_auth_module_name}" if self.send(arg) && self.send(arg) != ''
      end
    end
  
  end
end
