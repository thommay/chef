#
# Author:: Daniel DeLeo (<dan@kallistec.com>)
# Copyright:: Copyright (c) 2009 Daniel DeLeo
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

describe "Chef::WebUIUser" do

  before(:all) do
    # Next line is brutal, but we need to be sure that only the authentication we want is loaded!
    begin
      Chef.send(:remove_const,:WebUIUser)
    rescue
    end
    # Now we need to force the authentication modules to reload as the previous line removed them from memory
    # and they won't come back until we load the files again
    Dir[File.join(File.dirname(__FILE__),'..','..','lib','chef', 'web_ui_user', '*.rb')].sort.each { |lib| load lib }
    load File.join(File.dirname(__FILE__),'..','..','lib','chef','webui_user.rb')  
    Chef::Config.stub!(:[]).with(:web_ui_authentication_module).and_return(lambda{Chef::WebUIUser::CDBAuthModule})    
    Chef::WebUIUser.select_authorisation_module    
  end
  
  before do
    @webui_user = Chef::WebUIUser.new
  end

  it "should be using couchdb Class methods" do
    Chef::WebUIUser.auth_module_name.should == 'CDBAuthModuleClassMethods'
  end

  it "should be using couchdb Instance methods" do
    Chef::WebUIUser.new.instance_auth_module_name.should == 'CDBAuthModule'
  end
  
  it "stores the admin status of the user" do
    @webui_user.admin.should be_false
    @webui_user.admin = true
    @webui_user.admin.should be_true
    @webui_user.should be_admin
  end
  
  it "stores the name" do
    @webui_user.name.should be_nil
    @webui_user.name = "foo.bar.baz"
    @webui_user.name.should == "foo.bar.baz"
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
 
  describe "when setting or verifying a password" do
  
    it "raises an error when the password doesn't match the confirmation password" do
      lambda {@webui_user.cdb_set_password("nomnomnom", "yukyukyuk")}.should raise_error(ArgumentError, /do not match/)
    end
    
    it "doesn't allow blank passwords" do
      lambda {@webui_user.cdb_set_password("", "")}.should raise_error(ArgumentError, /cannot be blank/)
    end
    
    it "doesn't allow passwords less than 6 characters" do
      lambda {@webui_user.cdb_set_password("2shrt", "2shrt")}.should raise_error(ArgumentError, /minimum of 6 characters/)
    end
    
    it "generates a salt and hashes the password when the password is valid" do
      @webui_user.cdb_set_password("valid_pw", "valid_pw")
      @webui_user.salt.should_not be_nil
      @webui_user.password.should match(/[0-9a-f]{32}/)
    end
    
    it "verifies a correct password" do
      @webui_user.cdb_set_password("valid_pw", "valid_pw")
      @webui_user.cdb_verify_password("valid_pw").should be_true
    end
    
    it "doesn't verify an incorrect password" do
      @webui_user.cdb_set_password("valid_pw", "valid_pw")
      @webui_user.cdb_verify_password("invalid_pw").should be_false
    end
  end
 
  describe "when setting or verifying a password via the new_password values" do

    before do
      @webui_user.name = "relaxed_test"
      @couchdb = mock("Chef::Couchdb")
      Chef::CouchDB.stub(:new).and_return(@couchdb)
      @couchdb.stub(:store).and_return(@couchdb)
      @couchdb.stub(:[]).and_return(1)
      @webui_user.instance_variable_set(:@couchdb, @couchdb)
    end

    it "raises an error when the password doesn't match the confirmation password" do
      @webui_user.new_password = "nomnomnom"
      @webui_user.confirm_new_password = "yukyukyuk"
      lambda {@webui_user.cdb_save}.should raise_error(ArgumentError, /do not match/)
    end
    
    it "won't change the password when none given" do
      @webui_user.cdb_set_password("validpassword", "validpassword")
      @webui_user.cdb_save
      @webui_user.new_password = ""
      @webui_user.confirm_new_password = ""
      lambda{@webui_user.cdb_save}
      @webui_user.cdb_verify_password("validpassword").should be true
    end
    
    it "doesn't allow passwords less than 6 characters" do
      @webui_user.new_password = "2shrt"
      @webui_user.confirm_new_password = "2shrt"
      lambda {@webui_user.cdb_save}.should raise_error(ArgumentError, /minimum of 6 characters/)
    end
    
    it "generates a salt and hashes the password when the password is valid" do
      @webui_user.new_password = "valid_pw"
      @webui_user.confirm_new_password = "valid_pw"
      @webui_user.cdb_save
      @webui_user.salt.should_not be_nil
      @webui_user.password.should match(/[0-9a-f]{32}/)
    end

    it "doesn't allow unencrypted passwords to persist a successful save" do
      @webui_user.new_password = "valid_pw"
      @webui_user.confirm_new_password = "valid_pw"
      @webui_user.cdb_save
      @webui_user.new_password.should_not == "valid_pw"
    end

    it "doesn't allow unencrypted password confirmations to persist a successful save" do
      @webui_user.new_password = "valid_pw"
      @webui_user.confirm_new_password = "valid_pw"
      @webui_user.cdb_save
      @webui_user.confirm_new_password.should_not == "valid_pw"
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

  describe "when doing CRUD operations via API with a complex username" do
    before do
      @webui_user.name = "cn=foo,dc=example,dc=com"
      @rest = mock("Chef::REST")
      Chef::REST.stub!(:new).and_return(@rest)
    end

    it "escapes the name before attempting to GET it" do
      @rest.should_receive(:get_rest).with("users/cn%3Dbar%2Cdc%3Dexample%2Cdc%3Dcom")
      Chef::WebUIUser.load("cn=bar,dc=example,dc=com")    
    end
    
    it "updates via PUT to the escaped name when saving" do
      @rest.should_receive(:put_rest).with("users/cn%3Dfoo%2Cdc%3Dexample%2Cdc%3Dcom", @webui_user)
      @webui_user.save
    end
    
    it "falls back to creating via POST if updating returns 404" do
      response = mock("Net::HTTPResponse", :code => "404")
      not_found = Net::HTTPServerException.new("404", response)
      @rest.should_receive(:put_rest).with("users/cn%3Dfoo%2Cdc%3Dexample%2Cdc%3Dcom", @webui_user).and_raise(not_found)
      @rest.should_receive(:post_rest).with("users", @webui_user)
      @webui_user.save
    end
    
    it "finds all users in the database including those with complex names via GET" do
      robots  = Chef::WebUIUser.new("name"=>"we=r@b@ts")
      happy   = Chef::WebUIUser.new("name"=>"are_happy_robots")
      query_results = [robots,happy]
      query_obj = mock("Chef::Search::Query")
      query_obj.should_receive(:search).with(:user).and_yield(query_results.first).and_yield(query_results.last)
      Chef::Search::Query.stub!(:new).and_return(query_obj)
      Chef::WebUIUser.list(true).should == {"we=r@b@ts" => robots, "are_happy_robots" => happy}
    end


    it "creates via POST" do
      @rest.should_receive(:post_rest).with("users", @webui_user)
      @webui_user.create
    end

    it "deletes itself with DELETE" do
      @rest.should_receive(:delete_rest).with("users/cn%3Dfoo%2Cdc%3Dexample%2Cdc%3Dcom")
      @webui_user.destroy
    end


  end
  
  describe "when doing CRUD operations to the DB" do
    before do
      @webui_user.name = "relaxed_test"
      @couchdb = mock("Chef::Couchdb")
      Chef::CouchDB.stub(:new).and_return(@couchdb)
      @webui_user.instance_variable_set(:@couchdb, @couchdb)
    end
    
    it "finds users by name" do
      @couchdb.should_receive(:load).with("webui_user", "test_user")
      Chef::WebUIUser.cdb_load("test_user")
    end
    
    it "finds all ids in the database" do
      couch_rows = {"one"=>"mos_def","two"=>"and","three"=>"talib_kweli"}.map do |key, val|
        {"key" => key, "value" => val}
      end
      couch_return_val = {"rows" => couch_rows}
      @couchdb.should_receive(:list).with("users", false).and_return(couch_return_val)
      Chef::WebUIUser.cdb_list.sort.should == %w{one two three}.sort
    end
    
    it "finds all documents in the database" do
      couch_rows = {"one"=>"mos_def","two"=>"and","three"=>"talib_kweli"}.map do |key, val|
        {"key" => key, "value" => val}
      end
      couch_return_val = {"rows" => couch_rows}
      @couchdb.should_receive(:list).with("users", true).and_return(couch_return_val)
      Chef::WebUIUser.cdb_list(true).sort.should == %w{mos_def and talib_kweli}.sort
    end
    
    it "updates and saves documents" do
      @couchdb.should_receive(:store).with("webui_user", "relaxed_test", @webui_user).and_return("rev"=>"run")
      @webui_user.cdb_save
      @webui_user.couchdb_rev.should == "run"
    end
    
    it "deletes itself" do
      @webui_user = Chef::WebUIUser.new("_rev" => "run", "name" => "relaxed_test")
      @couchdb.should_receive(:delete).with("webui_user", "relaxed_test", "run")
      @webui_user.cdb_destroy
    end
  end
  
  describe "when converting to/from JSON" do
    before do
      @webui_user.name = "test_user"
    end
    
    it "keeps type data so it can be deserialized" do
      @webui_user.to_json.should match(Regexp.escape('"json_class":"Chef::WebUIUser"'))
    end
    
    it "includes the name, salt, password, openid and admin status" do
      @webui_user = Chef::WebUIUser.new("name"=>"test_user","password"=>"pw","salt"=>"pirate","openid"=>"really?")
      @webui_user.admin = true
      json = @webui_user.to_json
      
      json.should match(Regexp.escape('"name":"test_user"'))
      json.should match(Regexp.escape('"password":"pw"'))
      json.should match(Regexp.escape('"salt":"pirate"'))
      json.should match(Regexp.escape('"openid":"really?"'))
      json.should match(Regexp.escape('"admin":true'))
    end
    
    it "includes the couchdb _rev if available" do
      @webui_user = Chef::WebUIUser.new("_rev"=>"RuN")
      json = @webui_user.to_json
      json.should match(Regexp.escape('"_rev":"RuN"'))
    end
    
    it "includes the couchdb _id if available" do
      @webui_user = Chef::WebUIUser.new("_id"=>"ego")
      json = @webui_user.to_json
      json.should match(Regexp.escape('"_id":"ego"'))
    end
  end
  
  describe "behaving like a couch-able (relaxed?) object (cf CHEF-864)" do
    it "has an attr reader for couchdb_id" do
      @webui_user.should_not respond_to(:couchdb_id=)
      @webui_user.should respond_to(:couchdb_id)
      @webui_user.instance_variable_set(:@couchdb_id, "a big long UUID")
      @webui_user.couchdb_id.should == "a big long UUID"
    end
    
    it "sets its couchdb id when loading from the database" do
      # reqs via REST eventually get to JSON.parse
      webui_user = JSON.parse('{"salt":null,"name":"test_user","json_class":"Chef::WebUIUser","admin":false,"openid":null,"password":null,"chef_type":"webui_user","_id":"IdontNeedNoID"}')
      webui_user.couchdb_id.should == "IdontNeedNoID"
    end
    
    it "has an attr reader for couchdb_rev" do
      @webui_user.should_not respond_to(:couchdb_rev=)
      @webui_user.should respond_to(:couchdb_rev)
      @webui_user.instance_variable_set(:@couchdb_rev, "a couchdb version string")
      @webui_user.couchdb_rev.should == "a couchdb version string"
    end
    
    it "sets the couchdb_rev when loading from the database" do
      webui_user = JSON.parse('{"salt":null,"name":"test_user","json_class":"Chef::WebUIUser","admin":false,"openid":null,"password":null,"chef_type":"webui_user","_id":"IdontNeedNoID","_rev":"moto"}')
      webui_user.couchdb_rev.should == "moto"
    end
  end
  
end
