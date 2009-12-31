#
# Author:: Adam Jacob (<adam@opscode.com>)
# Author:: Christopher Brown (<cb@opscode.com>)
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

require 'chef' / 'node'

class ChefServerSlice::Nodes < ChefServerSlice::Application
  
  provides :html, :json
  
  before :fix_up_node_id
  before :login_required
  before :authorized_node, :only => [ :update, :destroy ]
  
  def index
    @node_list = Chef::Node.list 
    display(@node_list.collect { |n| absolute_slice_url(:node, escape_node_id(n)) })
  end

  def show
    begin
      @node = Chef::Node.load(params[:id])
    rescue Net::HTTPServerException => e
      raise NotFound, "Cannot load node #{params[:id]}"
    end
    # TODO - might as well expand the run list here, too, rather than take multiple round trips.
    recipes, defaults, overrides = @node.run_list.expand("couchdb")
    @node.default = defaults
    @node.override = overrides
    display @node
  end

  def new
    @node = Chef::Node.new
    @available_recipes = get_available_recipes 
    @available_roles = Chef::Role.list.sort
    @run_list = @node.run_list
    render
  end

  def edit
    begin
      @node = Chef::Node.load(params[:id])
    rescue Net::HTTPServerException => e
      raise NotFound, "Cannot load node #{params[:id]}"
    end
    @available_recipes = get_available_recipes 
    @available_roles = Chef::Role.list.sort
    @run_list = @node.run_list
    render
  end

  def create
    if params.has_key?("inflated_object")
      @node = params["inflated_object"]
      exists = true
      begin
        Chef::Node.load(@node.name)
      rescue Net::HTTPServerException
        exists = false
      end
      raise Forbidden, "Node already exists" if exists
      self.status = 201
      @node.save
      display({ :uri => absolute_slice_url(:node, escape_node_id(@node.name)) })
    else
      begin
        @node = Chef::Node.new
        @node.name params[:name]
        @node.attribute = JSON.parse(params[:attributes])
        @node.run_list params[:for_node]
        @node.save
        redirect(slice_url(:nodes), :message => { :notice => "Created Node #{@node.name}" })
      rescue Exception => e
        Chef::Log.error("Exception creating node: #{e.message}")
        @node.attribute = JSON.parse(params[:attributes])
        @available_recipes = get_available_recipes 
        @available_roles = Chef::Role.list.sort
        @run_list = params[:for_node] 
        @_message = { :error => "Exception raised creating node, please check logs for details" }
        render :new
      end
    end
  end

  def update
    begin
      @node = Chef::Node.load(params[:id])
    rescue Net::HTTPServerException => e
      raise NotFound, "Cannot load node #{params[:id]}"
    end

    if params.has_key?("inflated_object")
      updated = params['inflated_object']
      @node.run_list.reset(updated.run_list)
      @node.attribute = updated.attribute
      @node.save
      display(@node)
    else
      begin
        @node.run_list.reset(params[:for_node] ? params[:for_node] : [])
        @node.attribute = JSON.parse(params[:attributes])
        @node.save
        @_message = { :notice => "Updated Node" }
        render :show
      rescue Exception => e
        Chef::Log.error("Exception updating node: #{e.message}")
        @available_recipes = get_available_recipes 
        @available_roles = Chef::Role.list.sort
        @run_list = Chef::RunList.new
        @run_list.reset(params[:for_node])
        @_message = { :error => "Exception raised updating node, please check logs for details" }
        render :edit
      end
    end
  end

  def destroy
    begin
      @node = Chef::Node.load(params[:id])
    rescue Net::HTTPServerException => e 
      raise NotFound, "Cannot load node #{params[:id]}"
    end
    @node.destroy
    if request.accept == 'application/json'
      display @node
    else
      redirect(absolute_slice_url(:nodes), {:message => { :notice => "Node #{params[:id]} deleted successfully" }, :permanent => true})
    end
  end
  
end
