# Copyright (c) 2009 Paolo Capriotti <p.capriotti@gmail.com>
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

require 'toolkit'
require 'plugins/plugin'
require 'action_provider'
require_bundle 'ics', 'protocol'
require_bundle 'ics', 'connection'
require_bundle 'ics', 'match_handler'
require_bundle 'ics', 'preferences'
require_bundle 'ics', 'config'

class ICSPlugin
  include Plugin
  include ActionProvider
  
  class ICSView
    def initialize(view)
      @view = view
    end
    
    def main
      if not @main or @main.closed?
        @main = create(:name => 'ICS')
      end
      @main
    end
    
    def create(opts = { })
      @view.create(opts)
    end
    
    def activate(user, name)
      @view.activate(user, name)
    end
  end
  
  plugin :name => 'ICS Plugin',
         :interface => :action_provider
    
  attr_reader :gui
  
  def initialize
    @gui = KDE::gui(:icsplugin) do |g|
      g.menu_bar do |mb|
        mb.menu(:game) do |m|
          m.action :connect, :group => :file_extensions
          m.action :disconnect, :group => :file_extensions
        end
        mb.menu(:settings) do |m|
          m.action :configure_ics
        end
      end
      g.tool_bar(:ics_toolbar, :text => KDE::i18n("&ICS Toolbar")) do |tb|
        tb.action :connect
        tb.action :disconnect
      end
    end
    
    action(:connect,
           :text => KDE.i18n("&Connect to ICS"),
           :icon => 'network-connect') do |parent|
      connect_to_ics(parent)
    end
    action(:disconnect,
           :text => KDE.i18n("&Disconnect from ICS"),
           :icon => 'network-disconnect') do |parent|
      if @connection
        @connection.stop
        @connection = nil
        if @console_obs
          parent.console.delete_observer(@console_obs)
          @console_obs = nil
        end
      end
    end
    action(:configure_ics,
           :icon => 'network-workgroup',
           :text => KDE.i18n("Configure &ICS...")) do |parent|
      dialog = ICS::Preferences.new(parent)
      dialog.show
    end
  end
  
  def connect_to_ics(parent)
    protocol = ICS::Protocol.new(:debug)
    @connection = ICS::Connection.new('freechess.org', 23)
    config = ICS::Config.load
    protocol.add_observer ICS::AuthModule.new(@connection, 
      config[:username], config[:password])
    protocol.add_observer ICS::StartupModule.new(@connection)
    protocol.link_to @connection

    protocol.on :text do |text|
      parent.console.append(text)
    end

    @console_obs = parent.console.observe :input do |text|
      if @connection
        @connection.send_text text
      end
    end

    # create an ICS view
    @view = ICSView.new(parent.view)
    @handler = ICS::MatchHandler.new(@view, protocol)
    @connection.start
  end
end
