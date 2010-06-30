#
# Author:: Richard Nicholas (<richard.nicholas@betfair.com>)
# Copyright:: Copyright (c) 2010 
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

require File.expand_path(File.join(File.dirname(__FILE__), "..", "spec_helper"))

describe Chef::WebUIUser, "with LDAP authentication module" do
 
  before(:all) do
    # Next line is brutal, but we need to be sure that only the authentication we want is loaded!
    begin
      Chef.send(:remove_const,:WebUIUser)
    rescue
    end
    Dir[File.join(File.dirname(__FILE__),'..','..','lib','chef', 'web_ui_user', '*.rb')].sort.each { |lib| load lib }
    load File.join(File.dirname(__FILE__),'..','..','lib','chef','webui_user.rb')          
    Chef::Config.stub!(:[]).with(:web_ui_authentication_module).and_return(lambda{Chef::WebUIUser::LDAPAuthModule})
    Chef::WebUIUser.select_authentication_module    
  end
  
  before(:each) do
    @webui_user = Chef::WebUIUser.new  
    Chef::Config.stub!(:[]).with(:ldap_hosts).and_return(["fail_ldap_host","work_ldap_host"])
    Chef::Config.stub!(:[]).with(:ldap_port).and_return(389)
    Chef::Config.stub!(:[]).with(:ldap_bind_user).and_return("bobby@example.com")
    Chef::Config.stub!(:[]).with(:ldap_bind_password).and_return("valid_password")
    Chef::Config.stub!(:[]).with(:ldap_chef_user_groups).and_return("cn=chef_user_group,dc=example,dc=com")
    Chef::Config.stub!(:[]).with(:ldap_chef_admin_groups).and_return(["cn=chef_admin_group,dc=example,dc=com","cn=other_chef_admin_group,dc=example,dc=com"])
    Chef::Config.stub!(:[]).with(:ldap_user_attribute).and_return("sAMAccountName")
    Chef::Config.stub!(:[]).with(:ldap_group_attribute).and_return("memberOf")
    Chef::Config.stub!(:[]).with(:ldap_base_root).and_return("dc=example,dc=com")
  end
  
  it "should be using LDAP instance methods" do
    Chef::WebUIUser.new.instance_auth_module_name.should == "LDAPAuthModule"
  end
  
  it "should be using LDAP class methods" do
    Chef::WebUIUser.auth_module_name.should == "LDAPAuthModuleClassMethods"
  end


      
  it "can be initialized with a hash to set instance variables" do
    opt_hsh = {'name'=>'mud', 'salt'=>'just_a_lil', 'password'=>'beefded',
               'openid'=>'notsomuch', '_rev'=>'0', '_id'=>'tehid',
               'new_password'=>'blahblah', 'confirm_new_password'=>'blahblahtoo'}
    webui_user = Chef::WebUIUser.new(opt_hsh)
    webui_user.name.should        == 'mud'
    webui_user.salt.should        == 'just_a_lil'
    webui_user.password.should    == 'beefded'
    webui_user.openid.should      == 'notsomuch'
    webui_user.couchdb_rev.should == '0'
    webui_user.couchdb_id.should  == 'tehid'
    webui_user.new_password.should  == 'blahblah'
    webui_user.confirm_new_password.should  == 'blahblahtoo'
  end
  
  describe "when bad authentication module is selected" do
  
    it "should raise an error if a string is supplied" do
      Chef::Config.stub!(:[]).with(:web_ui_authentication_module).and_return('Chef::WebUIUser::LDAPAuthModule')  
      lambda {Chef::WebUIUser.select_authorisation_module}.should raise_error(NoMethodError)
    end

    it "should raise an error if a non existing module is selected" do
      Chef::Config.stub!(:[]).with(:web_ui_authentication_module).and_return(lambda{Chef::WebUIUser::NonExistantModule})  
      lambda {Chef::WebUIUser.select_authorisation_module}.should raise_error(NameError)
    end

  
  end

  describe Chef::WebUIUser::LDAPConnection do
  
    before do
      @ldap_conn = mock("Net::LDAP")
      @ldap_user = mock("Net::LDAP::Entry")
      Net::LDAP.stub(:new).and_return(@ldap_conn)
      @ldap_conn.stub(:bind).and_return(true)
      @ldap_conn.stub(:host=)
      @ldap_conn.stub(:search).and_return([@ldap_user])
      @ldap_user.stub(:memberOf).and_return(["cn=random_group,dc=example,dc=com","cn=other_chef_admin_group,dc=example,dc=com"])
    end
    
    it "should be a kind of LDAPConnection" do
      Chef::WebUIUser::LDAPConnection.new.should be_an_instance_of Chef::WebUIUser::LDAPConnection
    end
    
    it "can be initialised with a hash to set instance variables" do
      opt_hsh = {'port'=>1234, 'hosts'=>["mum","dad"], 'encrypt'=>"brzt%!", 
                 'username' => "bind_user", 'password' => "a_password"}    
      ldc = Chef::WebUIUser::LDAPConnection.new(opt_hsh)
      ldc.instance_variable_get(:@port).should == 1234
      ldc.instance_variable_get(:@hosts).should == ["mum","dad"]
      ldc.instance_variable_get(:@method).should == :simple_tls
      ldc.instance_variable_get(:@auth).should == {:method=>:simple,:username=>"bind_user",:password=>"a_password"}
    end
    
    it "can be initialised without encryption with a hash to set instance variables" do
      opt_hsh = {'port'=>1234, 'hosts'=>["mum","dad"], 'encrypt'=>false }    
      ldc = Chef::WebUIUser::LDAPConnection.new(opt_hsh)
      ldc.instance_variable_get(:@port).should == 1234
      ldc.instance_variable_get(:@hosts).should == ["mum","dad"]
      ldc.instance_variable_get(:@method).should == nil
    end
              
    it "should bind given hosts that connect" do
      Chef::WebUIUser::LDAPConnection.new.bind.should be_true
    end
    
    it "should bind to the second host if the first bind fails" do
      @ldap_conn.stub(:bind).and_return(false,true)
      @ldap_conn.should_receive(:host=).once.with("fail_ldap_host")
      @ldap_conn.should_receive(:host=).once.with("work_ldap_host")
      Chef::WebUIUser::LDAPConnection.new.bind
    end
    
    it "should bind to the first host if the first bind succeeds" do
      @ldap_conn.stub(:bind).and_return(true)
      @ldap_conn.should_receive(:host=).once.with("fail_ldap_host")
      Chef::WebUIUser::LDAPConnection.new.bind
    end
    
    it "should attempt twice and fail if the first bind fails" do    
      @ldap_conn.stub(:bind).and_return(false)
      @ldap_conn.should_receive(:host=).once.with("fail_ldap_host")
      @ldap_conn.should_receive(:host=).once.with("work_ldap_host")
      Chef::WebUIUser::LDAPConnection.new.bind.should == false
    end
    
    it "should bind_as the supplied credentials" do
      @ldap_conn.should_receive(:bind_as).once.with(:base=>"dc=example,dc=com",:filter=>"(sAMAccountName=Spongebob)",:password=>"Squarepants").and_return([Chef::WebUIUser::LDAPUser.new])
      Chef::WebUIUser::LDAPConnection.new.bind_as("Spongebob","Squarepants")
    end
    
    it "should perform complex binds controlled by lambdas" do
      Chef::Config.stub(:[]).with(:ldap_base_root).and_return( lambda {|n| "dc=#{n.split("\\").first},dc=example,dc=com"} )
      Chef::Config.stub(:[]).with(:ldap_user_preprocess).and_return( lambda {|n| "#{n.split("\\").last}"} )
      Chef::Config.stub(:[]).with(:ldap_user_attribute).and_return( lambda {|n| "(&(sAMAccountName=#{Chef::WebUIUser::LDAPConnection.ldap_escape(n)})(extraCheck=1234))"} )      
      @ldap_conn.should_receive(:bind_as).once.with(:base=>"dc=mydom,dc=example,dc=com",:filter=>"(&(sAMAccountName=Spongebob)(extraCheck=1234))",:password=>"Squarepants").and_return([Chef::WebUIUser::LDAPUser.new])
      Chef::WebUIUser::LDAPConnection.new.bind_as("mydom\\Spongebob","Squarepants")
    end
    
    it "should perform complex binds with lambdas passed as parameters" do
      @ldap_conn.should_receive(:bind_as).once.with(:base=>"dc=mydom,dc=example,dc=com",:filter=>"(&(sAMAccountName=Spongebob)(extraCheck=1234))",:password=>"Squarepants")
      Chef::WebUIUser::LDAPConnection.new.bind_as("mydom\\Spongebob","Squarepants", 
                                                  lambda {|n| "dc=#{n.split("\\").first},dc=example,dc=com"},
                                                  lambda {|n| "(&(sAMAccountName=#{Chef::WebUIUser::LDAPConnection.ldap_escape(n)})(extraCheck=1234))"},
                                                  lambda {|n| "#{n.split("\\").last}"} )
    end
   
    it "should perform searches" do
      @ldap_conn.should_receive(:search).once.with(:base=>"dc=example,dc=com",:filter=>"(sAMAccountName=Spongebob)")
      Chef::WebUIUser::LDAPConnection.new.ldap_search_for("Spongebob")
    end
    
    it "should perform searches with lambdas passed as parameters" do
      @ldap_conn.should_receive(:search).once.with(:base=>"dc=mydom,dc=example,dc=com",:filter=>"(&(sAMAccountName=Spongebob)(extraCheck=1234))")
      Chef::WebUIUser::LDAPConnection.new.ldap_search_for("mydom\\Spongebob", 
                                                  lambda {|n| "dc=#{n.split("\\").first},dc=example,dc=com"},
                                                  lambda {|n| "(&(sAMAccountName=#{Chef::WebUIUser::LDAPConnection.ldap_escape(n)})(extraCheck=1234))"},
                                                  lambda {|n| "#{n.split("\\").last}"} )
    end
    
    it "should perform searches with lambdas as the default settings" do
      Chef::Config.stub(:[]).with(:ldap_base_root).and_return( lambda {|n| "dc=#{n.split("\\").first},dc=example,dc=com"} )
      Chef::Config.stub(:[]).with(:ldap_user_preprocess).and_return( lambda {|n| "#{n.split("\\").last}"} )
      Chef::Config.stub(:[]).with(:ldap_user_attribute).and_return( lambda {|n| "(&(sAMAccountName=#{Chef::WebUIUser::LDAPConnection.ldap_escape(n)})(extraCheck=1234))"} )      
      @ldap_conn.should_receive(:search).once.with(:base=>"dc=mydom,dc=example,dc=com",:filter=>"(&(sAMAccountName=Spongebob)(extraCheck=1234))")
      Chef::WebUIUser::LDAPConnection.new.ldap_search_for("mydom\\Spongebob")
    end
    
    it "should escape usernames to prevent LDAP paramete injection" do
      @ldap_conn.should_receive(:search).once.with(:base=>"dc=example,dc=com",:filter=>"(sAMAccountName=Spongebob\\2a\\29\\28cn=\\2a\\29)" )
      Chef::WebUIUser::LDAPConnection.new.ldap_search_for("Spongebob*)(cn=*)")
    end
  
  end
    
  describe "when setting a password" do

    it "raises an error when an attempt is made to set the password" do
      lambda {@webui_user.cdb_set_password("valid_pwd", "valid_pwd")}.should raise_error(ArgumentError, /Passwords are controlled by the LDAP provider/)
    end
  
  end

  describe "when setting or verifying a password via the new_password values" do

    before do
      @webui_user.name = "ldap_test_user"
      @ldap_conn = mock("Net::LDAP")
      @ldap_user = mock("Net::LDAP::Entry")
      Net::LDAP.stub(:new).and_return(@ldap_conn)
      @ldap_conn.stub(:bind).and_return(true)
      @ldap_conn.stub(:host=)
      @ldap_conn.stub(:search).and_return([@ldap_user])
      @ldap_user.stub(:[]).with("memberOf").and_return(["cn=random_group,dc=example,dc=com","cn=other_chef_admin_group,dc=example,dc=com"])
      @couchdb = mock("Chef::CouchDB")
      Chef::CouchDB.stub(:new).and_return(@couchdb)        
      @couchdb.stub(:[]).with("rev").and_return(1)      
      @couchdb.stub(:store).and_return(@couchdb)      
    end

    it "won't change the password when none given" do
      @webui_user.new_password = ""
      @webui_user.confirm_new_password = ""
      lambda{@webui_user.cdb_save}.should_not raise_error
    end
    
    it "keeps bad password values when a save fails due to password problems" do
      @webui_user.new_password = "2shrt"
      @webui_user.confirm_new_password = "2shrt"
      lambda {@webui_user.cdb_save}
      @webui_user.new_password.should == "2shrt"
    end

    it "keeps bad confirm_password values when a save fails due to password problems" do
      @webui_user.new_password = "validpassword"
      @webui_user.confirm_new_password = "incorrectpass"
      lambda {@webui_user.cdb_save}
      @webui_user.confirm_new_password.should == "incorrectpass"
    end
    
    it "should raise an error when a new password is set" do
      @webui_user.new_password = "validpassword"
      @webui_user.confirm_new_password = "validpassword"
      lambda {@webui_user.cdb_save}.should raise_error(ArgumentError, "new_password cannot be set with the LDAPAuthModule")
    end

  end

  describe "when doing CRUD operations via API" do
  
    before do
      @webui_user.name = "test_user"
      @rest = mock("Chef::REST")
      Chef::REST.stub!(:new).and_return(@rest)
    end
    
    it "finds users by name via GET" do
      @rest.should_receive(:get_rest).with("users/mud")
      Chef::WebUIUser.load("mud")
    end
    
    it "finds all ids in the database via GET" do
      @rest.should_receive(:get_rest).with("users")
      Chef::WebUIUser.list
    end 
    
    it "finds all documents in the database via GET" do
      robots  = Chef::WebUIUser.new("name"=>"we_robots")
      happy   = Chef::WebUIUser.new("name"=>"are_happy_robots")
      query_results = [robots,happy]
      query_obj = mock("Chef::Search::Query")
      query_obj.should_receive(:search).with(:user).and_yield(query_results.first).and_yield(query_results.last)
      Chef::Search::Query.stub!(:new).and_return(query_obj)
      Chef::WebUIUser.list(true).should == {"we_robots" => robots, "are_happy_robots" => happy}
    end
    
    it "updates via PUT when saving" do
      @rest.should_receive(:put_rest).with("users/test_user", @webui_user)
      @webui_user.save
    end
    
    it "falls back to creating via POST if updating returns 404" do
      response = mock("Net::HTTPResponse", :code => "404")
      not_found = Net::HTTPServerException.new("404", response)
      @rest.should_receive(:put_rest).with("users/test_user", @webui_user).and_raise(not_found)
      @rest.should_receive(:post_rest).with("users", @webui_user)
      @webui_user.save
    end
    
    it "creates via POST" do
      @rest.should_receive(:post_rest).with("users", @webui_user)
      @webui_user.create
    end
    
    it "deletes itself with DELETE" do
      @rest.should_receive(:delete_rest).with("users/test_user")
      @webui_user.destroy
    end
    
  end
 
  describe "when loading a user that isn't in the couch DB but is in the LDAP data stores" do
  
    before do
      @ldap_conn = mock("Net::LDAP")
      @ldap_user = mock("Net::LDAP::Entry")
      Net::LDAP.stub(:new).and_return(@ldap_conn)
      @ldap_conn.stub(:bind).and_return(true)
      @ldap_conn.stub(:host=)
      @ldap_conn.stub(:search).and_return([@ldap_user])
      @ldap_user.stub("sAMAccountName").and_return("ldap_test_user")      
      @ldap_user.stub(:[]).with("memberOf").and_return(["cn=random_group,dc=example,dc=com","cn=other_chef_admin_group,dc=example,dc=com"])
      @couchdb = mock("Chef::CouchDB")
      Chef::CouchDB.stub(:new).and_return(@couchdb)
      @couchdb.stub(:[]).with("rev").and_return(1)
      new_u = Chef::WebUIUser.new("name"=>'ldap_test')
      @couchdb.stub(:load).with("webui_user","ldap_test_user").and_raise(Chef::Exceptions::CouchDBNotFound)
    end

    it "should create an admin user when the user is in an Admin group in LDAP" do
      @couchdb.should_receive(:store) do |a,b,c|
        a.should == "webui_user"
        b.should == "ldap_test_user"
        c.should be_an_instance_of(Chef::WebUIUser)
        c.admin.should == true
        c.name.should == "ldap_test_user"
        {'rev'=>1}
      end
      Chef::WebUIUser.cdb_load("ldap_test_user")
    end
      
    it "should create a non admin user when the user is in a User group in LDAP" do
      @ldap_user.stub(:[]).with("memberOf").and_return(["cn=chef_user_group,dc=example,dc=com"])
      @couchdb.should_receive(:store) do |a,b,c|
        a.should == "webui_user"
        b.should == "ldap_test_user"
        c.should be_an_instance_of(Chef::WebUIUser)
        c.admin.should == false
        c.name.should == "ldap_test_user"
        {'rev'=>1}        
      end
      Chef::WebUIUser.cdb_load("ldap_test_user")
    end

    it "should create a non admin user when LDAP returns a single item instead of an array for memberOf" do
      @ldap_user.stub(:[]).with("memberOf").and_return("cn=chef_user_group,dc=example,dc=com")
      @couchdb.should_receive(:store) do |a,b,c|
        a.should == "webui_user"
        b.should == "ldap_test_user"
        c.should be_an_instance_of(Chef::WebUIUser)
        c.admin.should == false
        c.name.should == "ldap_test_user"
        {'rev'=>1}        
      end
      Chef::WebUIUser.cdb_load("ldap_test_user")
    end
       
    it "should raise a Not Found error when the LDAP user is not in a chef group" do
      @ldap_user.stub(:[]).with("memberOf").and_return(["cn=any_random_group,dc=example,dc=com"])
      lambda{Chef::WebUIUser.cdb_load("ldap_test_user")}.should raise_error(Chef::Exceptions::CouchDBNotFound)
    end

    it "should raise a Not Found error when the LDAP user has a single memberOf and it is not a Chef group" do
      @ldap_user.stub(:[]).with("memberOf").and_return("cn=any_random_group,dc=example,dc=com")
      lambda{Chef::WebUIUser.cdb_load("ldap_test_user")}.should raise_error(Chef::Exceptions::CouchDBNotFound)
    end
    
    it "should raise a Not Found error when the LDAP user returns nil for memberOf" do
      @ldap_user.stub(:[]).with("memberOf").and_return(nil)
      lambda{Chef::WebUIUser.cdb_load("ldap_test_user")}.should raise_error(Chef::Exceptions::CouchDBNotFound)
    end
    
    it "should raise a Not Found error when the LDAP user returns an empty array for memberOf" do
      @ldap_user.stub(:[]).with("memberOf").and_return([])
      lambda{Chef::WebUIUser.cdb_load("ldap_test_user")}.should raise_error(Chef::Exceptions::CouchDBNotFound)
    end
    



  end  
end
