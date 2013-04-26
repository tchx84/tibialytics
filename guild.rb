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

require './character.rb'

TIBIA_MID_LEVEL = 100
GUILD_MAX_SCORE = 10000.0

GUILD_MODIFIERS_BOUNDS = nil
GUILD_FACTORS_BOUNDS = nil

class Array

  def sum
    return 0.0 if length == 0
    inject( nil ) { |sum,x| sum ? sum + x.to_f : x.to_f }
  end
  
  def average
    my_length = length
    my_length == 0 ? 0 : (sum.to_f / my_length)
  end

  def mean
    my_length = length
    return 0 if my_length == 0
    return self[my_length/2] if (my_length%2) != 0
    self[(my_length/2)-1]
  end
end

class Guild

  attr_accessor :members, :name, :friends, :victims, :killers, :assistances

  def initialize(name="", world="")
    @name = name
    @content = nil
    @members = []
    @world = world
    @threads = []
    @friends = []
    @assistances = []
    @victims = []
    @killers = []
  end

  def request
    @content = Content.new(:guild, @name).get!

    return false if @content.match("Internal error. Please try again later.")

    tables = @content.split("<TABLE")
    tables.each { |table|

      if table.match("Guild Members")
        rows = table.split("\n")
        rows.each { |row|

          match = nil
          if match=row.match(/\&name=(\w*|\+)*"/)
            member_name = match[0].split("=")[1].gsub(/\+|"/, " ").strip 

              character = Character.new(member_name)
              if character.request

                if character.is_foreigner?(@world)
                  puts "Member ignored: #{character.name} from #{character.world}"
                  next
                end

                @members.push(character)
              else
                puts "Member deleted: #{member_name}"
              end
              puts "Member added: #{character.name}"
          end
        }
      end
    }

    @members.sort! { |a,b| a.level < b.level ? 1 : -1 }

    true
  end

  def stats
    stats = ""
    
    stats +=  "\n#{@name} has #{size} members \n"
    stats += "----------------------------------------\n"    
    stats += "Total level         #{total}\n"
    stats += "Highest level       #{strongest.stats}\n"
    stats += "Median level        #{median.stats}\n"
    stats += "Lowest level        #{weakest.stats}\n"
    stats += "Average level       #{average}\n"
    stats += "Deads number        #{@killers.length} (-#{killers_modifier})\n"
    stats += "Kills number        #{@victims.length} (+#{victims_modifier})\n"
    stats += "Assistances number  #{@assistances.length} (+#{assistances_modifier})\n"
    stats += "Relatives number    #{@friends.length} (+#{friends_modifier})\n"
    stats += "----------------------------------------\n"
    stats += "Base factor         #{normalized_base_factor} (#{base_factor})\n"
    stats += "PvP factor          #{normalized_pvp_factor} (#{pvp_factor})\n"
    stats += "Community factor    #{normalized_social_factor} (#{social_factor})\n"
    stats += "----------------------------------------\n"
    stats += "Overall score       #{score}\n"
    stats += "\n"

    stats
  end

  def list
    members_list = "\nMembers list: \n"
    @members.each { |character| members_list += "#{character.stats}\n" }
    members_list += "\n"
    members_list
  end

  def size
    @members.length
  end

  def strongest
    @members.first ? @members.first : 0
  end

  def average
    ("%5.2f" % @members.collect(&:level).average).to_f
  end

  def mean
    @members.collect(&:level).mean
  end

  def weakest
    @members.last ? @members.last : 0 
  end

  def median
    @members.mean
  end

  def total
    @members.collect(&:level).sum
  end

  def friends_modifier
    friends_length = @friends.length.to_f
    return 0.0 if friends_length == 0.0

    friends_sum = @friends.sum.to_f
    friends_ratio = friends_length / size.to_f
    adjusted_modifier = friends_sum * friends_ratio

    ("%5.2f" % adjusted_modifier).to_f
  end

  def assistances_modifier
    victims_length = @victims.length.to_f
    return 0.0 if victims_length == 0.0

    assistances_length = @assistances.length.to_f
    return 0.0 if assistances_length == 0.0
  
    assistances_sum = @assistances.sum.to_f
    assistances_ratio = (assistances_length/victims_length)
    adjusted_modifier = assistances_sum * assistances_ratio

    ("%5.2f" % adjusted_modifier).to_f
  end

  def victims_modifier
    ("%5.2f" % @victims.sum).to_f
  end

  def killers_modifier
    ("%5.2f" % @killers.sum).to_f
  end

  def base_factor
    average_factor = (size * average).to_f
    mean_factor = (size * mean).to_f
    weakest_factor = (size * weakest.level).to_f
    strongest_factor = (size * strongest.level).to_f
    
    total_factor = average_factor+mean_factor+weakest_factor+strongest_factor
    average_factor = total_factor/4.0

    adjust_factor = (average - TIBIA_MID_LEVEL.to_f)*0.01
    weighted_factor = (average_factor*adjust_factor)

    plain_score = (average_factor+weighted_factor)
    ("%5.2f" % plain_score).to_f
  end

  def social_factor
    raise "No modifiers bounds found." if !GUILD_MODIFIERS_BOUNDS

    normal_factor = normalized_friends_modifier
    normal_factor += normalized_assistances_modifier

    ("%5.2f" % normal_factor).to_f
  end

  def pvp_factor
    kills = victims_modifier
    deads = killers_modifier
  
    return 0.0 if (kills + deads) == 0.0

    pvp_activity = ((kills + deads)/2.0)
    pvp_positive = (kills/pvp_activity)
    pvp_negative = (deads/pvp_activity)

    average_adjust = ((pvp_positive >= pvp_negative) ? (pvp_positive/pvp_negative) : (pvp_negative/pvp_positive))/2.0
    average_adjust = pvp_positive if pvp_negative == 0
    average_adjust = pvp_negative if pvp_positive == 0   
    average_adjust = 1.5 if average_adjust > 1.5 

    pvp_score = (pvp_activity * (pvp_positive < pvp_negative ? pvp_negative*-1.0 : pvp_positive*1.0))*average_adjust

    ("%5.2f" % pvp_score).to_f
  end

  def normalize(bounds, key, value)
    value_range = bounds[key][:upper] - bounds[key][:lower]
    normal_value = ((value - bounds[key][:lower])/value_range.to_f).to_f*GUILD_MAX_SCORE

    ("%5.2f" % normal_value).to_f
  end

  def normalized_assistances_modifier
    normalize(GUILD_MODIFIERS_BOUNDS, :assistances, assistances_modifier)
  end

  def normalized_friends_modifier
    normalize(GUILD_MODIFIERS_BOUNDS, :friends, friends_modifier)
  end

  def normalized_base_factor
    normalize(GUILD_FACTORS_BOUNDS, :base, base_factor)
  end

  def normalized_pvp_factor
    normalize(GUILD_FACTORS_BOUNDS, :pvp, pvp_factor)
  end

  def normalized_social_factor
    normalize(GUILD_FACTORS_BOUNDS, :social, social_factor)
  end
  
  def score
    raise "No factors bounds found." if !GUILD_FACTORS_BOUNDS

    normalized_total =  normalized_base_factor
    normalized_total += normalized_pvp_factor
    normalized_total += normalized_social_factor

    ("%5.2f" % (normalized_total/3.0)).to_f
  end

end

