# Copyright (c) 2010 Paolo Capriotti <p.capriotti@gmail.com>
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

require_bundle 'ics', 'style12'
require 'singleton'

module ICS

# 
# Helper mixin to create and start ICS matches.
# 
module MatchHelper
  #
  # Create an appropriate MatchHelper instance for the given style12
  # 
  def self.from_style12(style12)
    @@helpers ||= {}.tap do |h|
      h[Style12::Relation::EXAMINING] = ExaminingMatchHelper.instance
      h[Style12::Relation::NOT_MY_MOVE] = DefaultMatchHelper.instance
      h[Style12::Relation::MY_MOVE] = h[Style12::Relation::NOT_MY_MOVE]
      h[Style12::Relation::OBSERVING_PLAYED] = ObservingMatchHelper.instance
    end
    
    @@helpers[style12.relation]
  end
  
  # 
  # Get the helper instance for this type.
  # 
  # Currently supported types: :default, :examining, :observing.
  # 
  def self.get(type)
    ICS.const_get(type.to_s.capitalize + "MatchHelper").instance
  end
  
  # 
  # Create the opponent player. By default, create an ICSPlayer that
  # will respond to future style12 events.
  # 
  def create_opponent(protocol, color, match_info)
    send = lambda {|msg| protocol.connection.send_text(msg) }
    opponent = ICSPlayer.new(send, color, match_info[:match], match_info)
    match_info[:icsplayer] = opponent
    opponent
  end
  
  # 
  # Create a player for this match.
  # 
  def create_player(user, color, match_info)
    raise "not implemented"
  end
  
  # 
  # Create a new match instance.
  # 
  def create_match(handler, match_info)
    raise "not implemented"
  end
  
  # 
  # Close a match.
  # 
  def close_match(handler, match_info)
    handler.matches.delete(match_info[:game_number])
  end
  
  # 
  # Get user from the view. The default implementation
  # simply returns the controller of the main ics view.
  # 
  def get_user(view, match_info)
    view.main.controller
  end
  
  # 
  # Perform post-creation initialization for players.
  # 
  def setup_players(user, players)
  end
  
  # 
  # Return or create a match. Called on an existing match when a new style12 
  # event is received.
  # If no match for that style12 event is found, the match argument
  # will be nil.
  # 
  def get_match(handler, match_info, style12)
    match_info
  end
  
  # 
  # Return an array of colors to be assigned to the players.
  # 
  def colors(state, rel)
    turns = [state.turn, state.opposite_turn(state.turn)]
    if rel == Style12::Relation::NOT_MY_MOVE
      turns.reverse
    else
      turns
    end
  end
  
  # 
  # Start an existing match. Called when the first style12
  # for the given match is received.
  # 
  def start(protocol, view, match_info, style12)
    rel = style12.relation
    state = style12.state
    turns = [state.turn, state.opposite_turn(state.turn)]
    
    user_color, opponent_color = colors(state, rel)
        
    # create players
    opponent = create_opponent(protocol, opponent_color, match_info)
    user = get_user(view, match_info)
    player = create_player(user, user_color, match_info)
    setup_players(user, [player, opponent])
    
    # start match
    match = match_info[:match]
    match.register(player)
    match.register(opponent)
    match.start(player)
    match.start(opponent)
    raise "couldn't start match" unless match.started?
    
    # reset controller
    user.reset(match)
    
    # pad history with placeholders
    style12.move_index.times do
      match.history.add_placeholder
    end
    match.history.current = match.history.size - 1
    
    # set initial state and time
    unless match.valid_state? and 
           match_info[:icsapi].same_state(match.state, style12.state)
      match.history.state = style12.state
    end
    unless match.history.move
      move = match_info[:icsapi].parse_last_move(style12.last_move, style12.state.turn)
      match.history.move = move
      match.history.text = style12.last_move_san
    end
    match.update_time(style12.time)
    
    # activate view
    view.activate(user, match_name(match_info))
  end
  
  # 
  # A name for the match, to be displayed in the tab bar.
  # 
  def match_name(match_info)
    "#{match_info[:white][:name]} - #{match_info[:black][:name]}"
  end
end

#
# Helper class to setup normal ICS games.
# 
# The first player is the default user, and the opponent is a default
# ICSPlayer instance created by create_opponent.
# 
class DefaultMatchHelper
  include MatchHelper
  include Singleton

  def create_player(user, color, match_info)
    # do not create a new player, just return user
    user.color = color
    user.premove = true
    user.name = match_info[color][:name]
    user
  end
  
  def create_match(handler, match_info)
    match = Match.new(match_info[:game], 
        :kind => :ics,
        :editable => false,
        :time_running => true)
    match.on(:close) { close_match(handler, match_info) }
    match_info.merge(:match => match)
  end
  
  def close_match(handler, match_info)
    super(handler, match_info)
    handler.protocol.connection.send_text("resign")
  end
end

# 
# Helper class to setup matches in examination mode.
# 
# The first player is dummy, and the user is set to control both
# the dummy player and the opponent. This allows the user to perform
# moves for both players.
# 
class ExaminingMatchHelper
  include MatchHelper
  include Singleton
  
  def create_player(user, color, match_info)
    user.color = nil
    
    # create a controlled player
    player = DummyPlayer.new(color)
    player.name = match_info[color][:name]
    user.premove = false
    match_info[:match].add_observer(user)
    player
  end
  
  def setup_players(user, players)
    players.each do |player|
      user.add_controlled_player(player)
    end
  end

  def get_match(handler, match_info, style12)
    if match_info.nil?
      # Examined games on ics have no header, so we have to be prepared to
      # create a new match on the fly at this point.
      # Create an editable Game.dummy match for the moment.
      match_info = create_match(handler, style12.match_info)
      
      # We want to change the game type at some point, so request the game
      # movelist to the server.
      handler.protocol.connection.send_text('moves')
    end
    
    match_info
  end
  
  def create_match(handler, match_info)
    match = Match.new(Game.dummy, 
      :kind => :ics,
      :editable => true,
      :navigable => true)
    match.on(:close) { close_match(handler, match_info) }
    match_info.merge(:match => match)
  end
  
  def close_match(handler, match_info)
    super(handler, match_info)
    handler.protocol.connection.send_text("unexamine")
  end
end

# 
# Helper class to setup matches in observation mode.
# 
# Match is set to not editable and navigable, first player is dummy,
# no controlled player for the user.
# 
class ObservingMatchHelper
  include MatchHelper
  include Singleton
  
  def create_player(user, color, match_info)
    player = DummyPlayer.new(color)
    player.name = match_info[color][:name]
    user.premove = false
    match_info[:match].add_observer(user)
    player
  end
  
  def create_match(handler, match_info)
    match = Match.new(Game.dummy,
                      :kind => :ics,
                      :editable => false,
                      :navigable => false,
                      :time_running => true)
    match.on(:close) { close_match(handler, match_info) }
    match_info.merge(:match => match)
  end
  
  def close_match(handler, match_info)
    super(handler, match_info)
    handler.protocol.connection.send_text("unobserve #{match_info[:number]}")
  end
  
  def get_user(view, match_info)
    v = view.create(:name => match_name(match_info),
                    :activate => true)
    v.controller
  end
end

end
