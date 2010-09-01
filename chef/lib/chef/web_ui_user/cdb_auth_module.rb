#
# Author:: Richard Nicholas (<richard.nicholas@betfair.com>)
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

require "chef/couchdb"

class Chef
  class WebUIUser
    module CDBAuthModule

      def name=(n)
        # gsub no longer needed as names are URI escaped for use outside the REST API
        @name = n # .gsub(/\./, '_')
      end

      def set_openid(given_openid)
        @openid = given_openid
      end 

      def admin=(new_admin_status)
        @admin = new_admin_status
      end

      def couchdb=(couch_db_instance)
        @couchdb = couch_db_instance
      end

      def openid=(new_open_id)
        @openid = new_open_id
      end

      def couchdb
        @couchdb || Chef::CouchDB.new
      end 

      def self.included(base)
        base.extend Chef::WebUIUser::CDBAuthModuleClassMethods
      end

      # Set the password for this object.
      def cdb_set_password(password, confirm_password=password) 
        raise ArgumentError, "Passwords do not match" unless password == confirm_password
        raise ArgumentError, "Password cannot be blank" if (password.nil? || password.length==0)
        raise ArgumentError, "Password must be a minimum of 6 characters" if password.length < 6
        generate_salt
        @password = encrypt_password(password)      
      end

      # Verify the password for this object
      def cdb_verify_password(given_password)
        encrypt_password(given_password) == @password
      end 

      # Remove this WebUIUser from the CouchDB
      def cdb_destroy
        couchdb.delete("webui_user", @name, @couchdb_rev)
      end

      # Save this WebUIUser to the CouchDB
      def cdb_save
        cdb_set_password( @new_password, @confirm_new_password ) if @new_password
        @new_password, @confirm_new_password = nil, nil # Just to ensure that we don't save them!
        results = couchdb.store("webui_user", @name, self)
        @couchdb_rev = results["rev"]
        results
      end
      
      def instance_auth_module_name
        "CDBAuthModule"
      end      

    protected
  
      def generate_salt
        @salt = Time.now.to_s
        chars = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a
        30.times { @salt << chars[rand(chars.size-1)] }
        @salt
      end

      def encrypt_password(password)
        Digest::SHA1.hexdigest("--#{salt}--#{password}--")
      end

    end

    module CDBAuthModuleClassMethods

      DESIGN_DOCUMENT = {
        "version" => 3,
        "language" => "javascript",
        "views" => {
          "all" => {
            "map" => <<-EOJS
              function(doc) {
                if (doc.chef_type == "webui_user") {
                  emit(doc.name, doc);
                }
              }
            EOJS
          },
          "all_id" => {
            "map" => <<-EOJS
            function(doc) {
              if (doc.chef_type == "webui_user") {
                emit(doc.name, doc.name);
              }
            }
            EOJS
          },
        },
      } unless self.const_defined?("DESIGN_DOCUMENT")

      def auth_module_name
        'CDBAuthModuleClassMethods'
      end

      # List all the Chef::WebUIUser objects in the CouchDB.  If inflate is set to true, you will get
      # the full list of all registration objects.  Otherwise, you'll just get the IDs
      def cdb_list(inflate=false)
        rs = Chef::CouchDB.new.list("users", inflate)
        rs["rows"].collect { |r| r[inflate ? "value" : "key" ]}
      end

      # Load an WebUIUser by name from CouchDB
      def cdb_load(name)
        Chef::CouchDB.new.load("webui_user", name)
      end

      # Whether or not there is an WebUIUser with this key.
      def cdb_has_key?(name)
        Chef::CouchDB.new.has_key?("webui_user", name)
      end
    
      #return true if an admin user exists. this is pretty expensive (O(n)), should think of a better way (nuo)
      def cdb_admin_exist
        users = self.cdb_list
        users.any?{ |u| self.cdb_load(u).admin }
      end

      # Set up our CouchDB design document
      def create_design_document(couchdb=nil)
        couchdb ||= Chef::CouchDB.new
        couchdb.create_design_document("users", DESIGN_DOCUMENT)
      end

    end
  end
end
