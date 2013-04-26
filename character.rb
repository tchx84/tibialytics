# Copyright (c) 2010 Martin Abente Lahaye. - martin.abente.lahaye@gmail.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301, USA
#

require './content.rb'

class Character

  attr_accessor :name, :vocation, :level, :killers, :friends, :world

  def initialize(name="")
    @name = name
    @vocation = vocation
    @level = level
    @world = nil
    @content =  nil
    @friends = []
    @killers = []
  end

  def stats
    "#{@name} (#{@level}) #{@vocation}, Married to #{@friends.first ? @friends.first : "no one"}. Recently killed #{@killers.length} times."
  end

  def request
    @content = Content.new(:character, @name).get!

    return false if @content.match("\<b\>#{@name}\<\/b\> does not exist.")

    tables = @content.split("<table ")
    tables.each { |table|

        match = nil      
        if table.match("Character Information")

          table.gsub!(/\<\/td\>|\<td\>|\<\/tr\>|\<tr\>/, "")
          @vocation = table.match(/Vocation:(\w+\s*)+/)[0].split(":")[1].strip
          @level = table.match(/Level:\d*/)[0].split(":")[1].to_i
          @world  = table.match(/World:\w*/)[0].split(":")[1].strip
          if match=table.match(/\&name=(\w*|\+)*"/)
            friend_name = match[0].split("=")[1].gsub(/\+|"/, " ").strip
            @friends.push(friend_name)
          end
        end

        if table.match("Character Deaths")
          rows = table.split(/CEST/)
          rows.each { |row|

            if row.match(/Killed|Slain/)
                killers = []

                killers_raw = row.split(/character/)
                killers_raw.each { |killer_raw|
                  if match=killer_raw.match(/\&name=(\w*|\+)*"/)
                    killer_name = match[0].split("=")[1].gsub(/\+|"/, " ").strip
                    killers.push(killer_name)
                  end
                }
              
                @killers.push(killers)
            end
          }
        end

    }
    
    true
  end

  def is_foreigner?(world)
    return @world != world
  end

end

