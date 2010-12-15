# Copyright (c) 2009 Paolo Capriotti <p.capriotti@gmail.com>
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

require 'toolkit'

class ConstrainedTextItem < Qt::GraphicsItem
  attr_reader :text

  def initialize(text, parent, constraint = Qt::RectF.new, opts = {})
    super(parent)
    @text = text.to_s
    @parent = parent
    @constraint = constraint
    
    @font = opts[:font] || Qt::Font.new
    @fm = Qt::FontMetrics.new(@font)
    @color = opts[:color] || Qt::Color.new(Qt::black)
    
    update_metrics
  end
  
  def paint(p, opts, widget)
    p.pen = @color
    p.font = @font
    p.saving do
      p.translate(@constraint.center)
      p.scale(@factor, @factor)
      p.translate(-@brect_max.center)
      p.draw_text((@brect_max.width - @brect.width) / 2, 0, @text)
    end
  end
  
  def boundingRect
    @constraint
  end

  def text=(value)
    @text = value.to_s
    update_metrics
    update @constraint
  end
  
  def constraint=(value)
    @constraint = value
    update_metrics
    update @constraint
  end
  
  def color=(value)
    @color = value
    update @constraint
  end
  
  def update_metrics
    if @text.empty?
      @brect = @constraint
      @brect_max = @constraint
      @factor = 1.0
    else
      @brect = @fm.bounding_rect(@text)
      @brect_max = @fm.bounding_rect('H' * @text.size)
      @factor = [
        @constraint.width / @brect_max.width,
        @constraint.height / @brect_max.height].min
    end
  end
  
  alias :name :text  
end
