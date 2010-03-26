#
# Author:: Adam Jacob (<adam@opscode.com>)
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

require File.expand_path(File.join(File.dirname(__FILE__), "..", "spec_helper"))

describe Chef::CookbookLoader do
  before(:each) do
    Chef::Config.cookbook_path [ 
      File.join(File.dirname(__FILE__), "..", "data", "kitchen"),
      File.join(File.dirname(__FILE__), "..", "data", "cookbooks")
    ]
    @cl = Chef::CookbookLoader.new()
  end
  
  describe "initialize" do
    it "should be a Chef::CookbookLoader object" do
      @cl.should be_kind_of(Chef::CookbookLoader)
    end
  end
  
  describe "[]" do
    it "should return cookbook objects with []" do
      @cl[:openldap].should be_a_kind_of(Chef::Cookbook)
    end
  
  
    it "should raise an exception if it cannot find a cookbook with []" do
      lambda { @cl[:monkeypoop] }.should raise_error(ArgumentError)
    end
  
    it "should allow you to look up available cookbooks with [] and a symbol" do
      @cl[:openldap].name.should eql(:openldap)
    end
  
    it "should allow you to look up available cookbooks with [] and a string" do
      @cl["openldap"].name.should eql(:openldap)
    end
  end
  
  describe "each" do
    it "should allow you to iterate over cookbooks with each" do
      seen = Hash.new
      @cl.each do |cb|
        seen[cb.name] = true
      end
      seen.should have_key(:openldap)
      seen.should have_key(:apache2)
    end

    it "should iterate in alphabetical order" do
      seen = Array.new 
      @cl.each do |cb|
        seen << cb.name
      end
      seen[0].should == :apache2
      seen[1].should == :openldap
    end
  end

  describe "load_cookbooks" do
    it "should find all the cookbooks in the cookbook path" do
      Chef::Config.cookbook_path << File.join(File.dirname(__FILE__), "..", "data", "hidden-cookbooks") 
      @cl.load_cookbooks
      @cl.detect { |cb| cb.name == :openldap }.should_not eql(nil)
      @cl.detect { |cb| cb.name == :apache2 }.should_not eql(nil)
    end
  
    it "should load multiple versions of the same cookbook" do
      Chef::Config.cookbook_path << File.join(File.dirname(__FILE__), "..", "data", "grill") 
      @cl.load_cookbooks
      @cl.detect { |cb| cb.name == :openldap }.should_not eql(nil)
      @cl.detect { |cb| cb.name == :apache2 }.should_not eql(nil)
      @cl.cookbook[:openldap].length.should eql(2)
    end
  
    it "should allow you to override an attribute file via cookbook_path" do
      @cl[:openldap].attribute_files.detect { |f| 
        f =~ /cookbooks\/openldap\/attributes\/default.rb/
      }.should_not eql(nil)
      @cl[:openldap].attribute_files.detect { |f| 
        f =~ /kitchen\/openldap\/attributes\/default.rb/
      }.should eql(nil)
    end
  
    it "should load different attribute files from deeper paths" do
      @cl[:openldap].attribute_files.detect { |f| 
        f =~ /kitchen\/openldap\/attributes\/robinson.rb/
      }.should_not eql(nil)
    end
  
    it "should allow you to override a definition file via cookbook_path" do
      @cl[:openldap].definition_files.detect { |f| 
        f =~ /cookbooks\/openldap\/definitions\/client.rb/
      }.should_not eql(nil)
      @cl[:openldap].definition_files.detect { |f| 
        f =~ /kitchen\/openldap\/definitions\/client.rb/
      }.should eql(nil)
    end
  
    it "should load definition files from deeper paths" do
      @cl[:openldap].definition_files.detect { |f| 
        f =~ /kitchen\/openldap\/definitions\/drewbarrymore.rb/
      }.should_not eql(nil)
    end
  
    it "should allow you to override a recipe file via cookbook_path" do
      @cl[:openldap].recipe_files.detect { |f| 
        f =~ /cookbooks\/openldap\/recipes\/gigantor.rb/
      }.should_not eql(nil)
      @cl[:openldap].recipe_files.detect { |f| 
        f =~ /kitchen\/openldap\/recipes\/gigantor.rb/
      }.should eql(nil)
    end
  
    it "should load recipe files from deeper paths" do
      @cl[:openldap].recipe_files.detect { |f| 
        f =~ /kitchen\/openldap\/recipes\/woot.rb/
      }.should_not eql(nil)
    end
  
    it "should allow you to have an 'ignore' file, which skips loading files in later cookbooks" do
      @cl[:openldap].recipe_files.detect { |f| 
        f =~ /kitchen\/openldap\/recipes\/ignoreme.rb/
      }.should eql(nil)
    end
    
    it "should find files that start with a ." do
      @cl[:openldap].remote_files.detect { |f|
        f =~ /\.dotfile$/
      }.should =~ /\.dotfile$/
      @cl[:openldap].remote_files.detect { |f|
        f =~ /\.ssh\/id_rsa$/
      }.should =~ /\.ssh\/id_rsa$/
    end

    it "should load the metadata for the cookbook" do
      @cl.metadata(:openldap).name.should == "openldap"
      @cl.metadata(:openldap).should be_a_kind_of(Chef::Cookbook::Metadata)
    end

  end
  
end
