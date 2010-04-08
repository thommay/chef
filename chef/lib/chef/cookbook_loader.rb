#
# Author:: Adam Jacob (<adam@opscode.com>)
# Author:: Christopher Walters (<cw@opscode.com>)
# Author:: Daniel DeLeo (<dan@kallistec.com>)
# Copyright:: Copyright (c) 2008 Opscode, Inc.
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

require 'chef/config'
require 'chef/cookbook'
require 'chef/cookbook/metadata'
require 'chef/mixin/deep_merge'

class Chef
  class CookbookLoader
    
    attr_accessor :cookbook
    
    include Enumerable
    
    CMP = {
      "<<" => lambda { |v, r| v < r },
      "<=" => lambda { |v, r| v <= r },
      "="  => lambda { |v, r| v == r },
      ">=" => lambda { |v, r| v >= r },
      ">>" => lambda { |v, r| v > r }
    }

    qcmp = CMP.keys.map { |k| Regexp.quote k }.join "|"
    PATTERN = /\A\s*(#{qcmp})?\s*(#{Chef::Cookbook::Metadata::Version::PATTERN})\s*\z/

    def initialize()
      @cookbooks = Array.new
      @cookbook = Hash.new
      @ignore_regexes = Hash.new { |hsh, key| hsh[key] = Array.new }
      load_cookbooks
    end
    
    def load_cookbooks
      cookbook_settings = Hash.new
      [Chef::Config.cookbook_path].flatten.each do |cb_path|
        Dir[File.join(cb_path, "*")].each do |cookbook|
          next unless File.directory?(cookbook)          
          cookbook_name = File.basename(cookbook).to_sym
          cookbook_settings[cookbook_name] ||= Mash.new

          # If we have a metadata file, there's only one version of the cookbook, so
          # just process it.
          if File.exists?(File.join(cookbook, "metadata.json"))
            (ver, settings) = process_cb(cookbook, cookbook_name)
            if cookbook_settings[cookbook_name].has_key?(ver)
              cookbook_settings[cookbook_name][ver] = Chef::Mixin::DeepMerge.merge(cookbook_settings[cookbook_name][ver], settings)
            else
              cookbook_settings[cookbook_name][ver] = settings
            end
          # Solo mode doesn't require metadata or versions
          elsif Chef::Config[:solo] and File.directory?(File.join(cookbook, "recipes"))
            (ver, settings) = process_cb(cookbook, cookbook_name, "0.0")
            if cookbook_settings[cookbook_name].has_key?(ver)
              cookbook_settings[cookbook_name][ver] = Chef::Mixin::DeepMerge.merge(cookbook_settings[cookbook_name][ver], settings)
            else
              cookbook_settings[cookbook_name][ver] = settings
            end
          else
            # Otherwise, we've got a directory of versions of a specific cookbook. So we
            # need to read each one in turn.
            Dir[File.join(cookbook, "*")].each do |version|
              next unless File.directory?(version)
              (ver, settings) = process_cb(version, cookbook_name, File.basename(version))
              if cookbook_settings[cookbook_name].has_key?(ver)
                cookbook_settings[cookbook_name][ver] = Chef::Mixin::DeepMerge.merge(cookbook_settings[cookbook_name][ver], settings)
              else
                cookbook_settings[cookbook_name][ver] = settings
              end
            end
          end
        end
      end

      remove_ignored_files_from(cookbook_settings)
      
      cookbook_settings.each_key do |cookbook|
        @cookbook[cookbook] ||= Mash.new
        cookbook_settings[cookbook].each_key do |version|
          cb = Chef::Cookbook.new(cookbook)
          cb.attribute_files = cookbook_settings[cookbook][version][:attribute_files].values
          cb.definition_files = cookbook_settings[cookbook][version][:definition_files].values
          cb.recipe_files = cookbook_settings[cookbook][version][:recipe_files].values
          cb.template_files = cookbook_settings[cookbook][version][:template_files].values
          cb.remote_files = cookbook_settings[cookbook][version][:remote_files].values
          cb.lib_files = cookbook_settings[cookbook][version][:lib_files].values
          cb.resource_files = cookbook_settings[cookbook][version][:resource_files].values
          cb.provider_files = cookbook_settings[cookbook][version][:provider_files].values
          md = Chef::Cookbook::Metadata.new(cb)
          cookbook_settings[cookbook][version][:metadata_files].each do |meta_json|
            md.from_json(IO.read(meta_json))
          end
          @cookbooks << [cb,md]
          @cookbook[cookbook][version] = @cookbooks.length - 1
        end
      end
    end
    
    def [](cookbook)
      # if we just request a cookbook without a version, return the latest one
      if @cookbook.has_key?(cookbook.to_sym)
        pos = @cookbook[cookbook.to_sym][versions(cookbook).last]
        @cookbooks[pos][0]
      else
        raise ArgumentError, "Cannot find a cookbook named #{cookbook.to_s}; did you forget to add metadata to a cookbook? (http://wiki.opscode.com/display/chef/Metadata)"
      end
    end
    
    def metadata(cookbook, version=nil)
      if version
        @cookbooks[@cookbook[cookbook][version]][1]
      else
        pos = @cookbook[cookbook.to_sym][versions(cookbook).last]
        @cookbooks[pos][1]
      end
    end


    def each
      @cookbook.keys.sort { |a,b| a.to_s <=> b.to_s }.each do |cname|
        pos = @cookbook[cname][versions(cname).last]
        yield @cookbooks[pos][0]
      end
    end

    def satisfy_all(cookbook, reqs=[])
      vers = Array.new

      if reqs.nil? or reqs.empty?
        return self.load(cookbook, satisfy(cookbook).last)
      end

      reqs.each do |pat|
        v = satisfy(cookbook, pat)
        raise ArgumentError, "Can't satisfy dependency #{pat} for cookbook #{cookbook}" if v.empty?
        if vers.empty?
          vers = v
        else
          vers = vers & v
          raise ArgumentError, "Conflicting dependencies for #{cookbook}" if vers.empty?
        end
      end
      self.load(cookbook, vers.last)
    end

    def satisfy(cookbook, req=nil)
      if req.nil?
        versions(cookbook)
      elsif req =~ PATTERN
        comp = $1 || "="
        ver = Chef::Cookbook::Metadata::Version.new $2
        versions(cookbook).select { |v| CMP[comp].call Chef::Cookbook::Metadata::Version.new(v), ver}
      else
        raise ArgumentError, "Unrecognized dependency specification"
      end
    end


    def load(cookbook, version=nil)
      if @cookbook.has_key?(cookbook.to_sym)
        if version
          if @cookbook[cookbook.to_sym].has_key?(version)
            @cookbooks[@cookbook[cookbook.to_sym][version]]
          else
            raise ArgumentError, "Cannot find the requested version #{version} of cookbook #{cookbook}"
          end
        else
          pos = @cookbook[cookbook.to_sym][versions(cookbook).last]
          @cookbooks[pos]
        end
      else
        raise ArgumentError, "Cannot find a cookbook named #{cookbook.to_s}; did you forget to add metadata to a cookbook? (http://wiki.opscode.com/display/chef/Metadata)"
      end
    end

    def versions(cookbook)
      @cookbook[cookbook.to_sym].keys.sort { |a,b| Chef::Cookbook::Metadata::Version.new(a) <=> Chef::Cookbook::Metadata::Version.new(b) }
    end

    private
    
      def load_ignore_file(ignore_file)
        results = Array.new
        if File.exists?(ignore_file) && File.readable?(ignore_file)
          IO.foreach(ignore_file) do |line|
            next if line =~ /^#/
            next if line =~ /^\w*$/
            line.chomp!
            results << Regexp.new(line)
          end
        end
        results
      end
      
      def remove_ignored_files_from(cookbook_settings)
        file_types_to_inspect = [ :attribute_files, :definition_files, :recipe_files, :template_files, 
                                  :remote_files, :lib_files, :resource_files, :provider_files]
        
        @ignore_regexes.each do |cookbook_name, regexes|
          cookbook_settings[cookbook_name].each_key do |version|
            regexes.each do |regex|
              settings = cookbook_settings[cookbook_name][version]
              file_types_to_inspect.each do |file_type|
                settings[file_type].delete_if { |uniqname, fullpath| fullpath.match(regex) }
              end
            end
          end
        end
      end
      
      def load_cascading_files(file_glob, base_path, result_hash)
        rm_base_path = /^#{base_path}\/(.+)$/
        # To handle dotfiles like .ssh
        Dir.glob(File.join(base_path, "**/#{file_glob}"), File::FNM_DOTMATCH).each do |file|
          result_hash[rm_base_path.match(file)[1]] = file
        end
      end
      
      def load_files_unless_basename(file_glob, result_hash)
        Dir[file_glob].each do |file|
          result_hash[File.basename(file)] = file
        end
      end
      
      def process_cb(path, cookbook_name, version=nil)
        settings = { 
          :attribute_files  => Hash.new,
          :definition_files => Hash.new,
          :recipe_files     => Hash.new,
          :template_files   => Hash.new,
          :remote_files     => Hash.new,
          :lib_files        => Hash.new,
          :resource_files   => Hash.new,
          :provider_files   => Hash.new,
          :metadata_files   => Array.new
        }

        ignore_regexes = load_ignore_file(File.join(path, "ignore"))
        @ignore_regexes[cookbook_name].concat(ignore_regexes)

        load_files_unless_basename(
          File.join(path, "attributes", "*.rb"), 
          settings[:attribute_files]
        )
        load_files_unless_basename(
          File.join(path, "definitions", "*.rb"), 
          settings[:definition_files]
        )
        load_files_unless_basename(
          File.join(path, "recipes", "*.rb"), 
          settings[:recipe_files]
        )
        load_files_unless_basename(
          File.join(path, "libraries", "*.rb"),               
          settings[:lib_files]
        )
        load_cascading_files(
          "*.erb",
          File.join(path, "templates"),
          settings[:template_files]
        )
        load_cascading_files(
          "*",
          File.join(path, "files"),
          settings[:remote_files]
        )
        load_cascading_files(
          "*.rb",
          File.join(path, "resources"),
          settings[:resource_files]
        )
        load_cascading_files(
          "*.rb",
          File.join(path, "providers"),
          settings[:provider_files]
        )

        if File.exists?(File.join(path, "metadata.json"))
          settings[:metadata_files] << File.join(path, "metadata.json")
          unless version
            md = Chef::Cookbook::Metadata.from_json(IO.read(File.join(path, "metadata.json")))
            version = md.version
          end
        end
        return [version || "0.0.0", settings]
      end

  end
end
