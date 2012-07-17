# Alternative Augeas-based providers for Puppet
#
# Copyright (c) 2012 Raphaël Pinson
# Licensed under the Apache License, Version 2.0

require 'augeasproviders/provider'

Puppet::Type.type(:sshd_config).provide(:augeas) do
  desc "Uses Augeas API to update an sshd_config parameter"

  def self.file(resource = nil)
    file = "/etc/ssh/sshd_config"
    file = resource[:target] if resource and resource[:target]
    file.chomp("/")
  end

  confine :feature => :augeas
  confine :exists => file

  def self.augopen(resource = nil)
    AugeasProviders::Provider.augopen("Sshd.lns", file(resource))
  end

  def self.path_label(path)
    path.split("/")[-1]
  end

  def self.instances
    aug = nil
    begin
      resources = []
      aug = augopen
      aug.match("/files#{file}/*").each do |hpath|
        name = self.path_label(hpath)
        next if name.start_with?("#", "@")

        if name =~ /Match(\[\d\*\])?/
          conditions = Array.new()
          aug.match("#{hpath}/Condition/*").each do |cond_path|
            cond_name = self.path_label(cond_path)
            cond_value = aug.get(cond_path)
            conditions.push("#{cond_name} #{cond_value}")
          end
          cond_str = conditions.join(" ")
          aug.match("#{hpath}/Settings/*").each do |setting_path|
            setting_name = self.path_label(setting_path)
            entry = {:ensure => :present, :name => setting_name, :value => aug.get(setting_path), :condition => cond_str}
            resources << new(entry) if entry[:value]
          end
        else
          entry = {:ensure => :present, :name => name, :value => aug.get(hpath)}
          resources << new(entry) if entry[:value]
        end
      end
      resources
    ensure
      aug.close if aug
    end
  end

  def self.match_conditions(resource=nil)
    if resource[:condition]
      conditions = Hash[*resource[:condition].split(' ').flatten(1)]
      cond_keys = conditions.keys.length
      cond_str = "[count(Condition/*)=#{cond_keys}]"
      conditions.each { |k,v| cond_str += "[Condition/#{k}=\"#{v}\"]" }
      cond_str
    else
      ""
    end
  end

  def self.entry_path(resource)
    path = "/files#{self.file(resource)}"
    key = resource[:key] ? resource[:key] : resource[:name]
    if resource[:condition]
      cond_str = self.match_conditions(resource)
      "#{path}/Match#{cond_str}/Settings/#{key}"
    else
      "#{path}/#{key}"
    end
  end

  def self.match_exists?(resource)
    aug = nil
    path = "/files#{self.file(resource)}"
    begin
      aug = self.augopen(resource)
      if resource[:condition]
        cond_str = self.match_conditions(resource)
      else
        false
      end
      not aug.match("#{path}/Match#{cond_str}").empty?
    ensure
      aug.close if aug
    end
  end

  def exists? 
    aug = nil
    entry_path = self.class.entry_path(resource)
    begin
      aug = self.class.augopen(resource)
      not aug.match(entry_path).empty?
    ensure
      aug.close if aug
    end
  end

  def self.create_match(resource=nil, aug=nil)
    path = "/files#{self.file(resource)}"
    begin
      aug.insert("#{path}/*[last()]", "Match", false)
      conditions = Hash[*resource[:condition].split(' ').flatten(1)]
      conditions.each do |k,v|
        aug.set("#{path}/Match[last()]/Condition/#{k}", v)
      end
      aug
    end
  end

  def create 
    aug = nil
    path = "/files#{self.class.file(resource)}"
    entry_path = self.class.entry_path(resource)
    key = resource[:key] ? resource[:key] : resource[:name]
    begin
      aug = self.class.augopen(resource)
      if resource[:condition]
        unless self.class.match_exists?(resource)
          aug = self.class.create_match(resource, aug)
        end
      else
        unless aug.match("#{path}/Match").empty?
          aug.insert("#{path}/Match[1]", key, true)
        end
      end
      aug.set(entry_path, resource[:value])
      aug.save!
    ensure
      aug.close if aug
    end
  end

  def destroy
    aug = nil
    path = "/files#{self.class.file(resource)}"
    begin
      aug = self.class.augopen(resource)
      entry_path = self.class.entry_path(resource)
      aug.rm(entry_path)
      aug.rm("#{path}/Match[count(Settings/*)=0]")
      aug.save!
    ensure
      aug.close if aug
    end
  end

  def target
    self.class.file(resource)
  end

  def value
    aug = nil
    path = "/files#{self.class.file(resource)}"
    begin
      aug = self.class.augopen(resource)
      entry_path = self.class.entry_path(resource)
      aug.get(entry_path)
    ensure
      aug.close if aug
    end
  end

  def value=(thevalue)
    aug = nil
    path = "/files#{self.class.file(resource)}"
    begin
      aug = self.class.augopen(resource)
      entry_path = self.class.entry_path(resource)
      aug.set(entry_path, thevalue)
      aug.save!
    ensure
      aug.close if aug
    end
  end
end