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

require 'fileutils'
require './guild.rb'

VICTIM_PERCENT = 0.25
KILLER_PERCENT = 0.25
MARRIED_FRIEND_PERCENT = 0.25
BATTLE_FRIEND_PERCENT = 0.0655
GUILD_PERCENT = 0.005

class World

  attr_accessor :name, :guilds

  def initialize(name="")
    @name = name
    @guilds = []
    @content = nil
    @threads = []
    @outlaws = []
    @foreigners = []
  end

  def request
    @content = Content.new(:world, @name).get!

    tables = @content.split(/^\<TABLE/)
    tables.each { |table|

      if table.match("Active Guilds on")
        rows = table.split("\n")
        rows.each { |row|
           
          match = nil
          if match=row.match(/^\<TD\>\<B\>(\w*|\s*)+\</)
            guild_name = match[0].split("<B>")[1].gsub(/\</, " ").strip
 
              guild = Guild.new(guild_name, @name)
              if guild.request

                if guild.members.length == 0
                  puts "Guild ignored: #{guild.name}"
                  next
                end

                @guilds.push(guild)
              else
                puts "Guild error: #{guild_name}"
              end

              puts "Guild added #{guild_name}"
          end
        }
      end
    }

    true
  end

  def generate_ranking
    update_social_modifiers!
    update_social_modifiers_outlaws!
    update_guild_factors_bounds!
    @guilds.sort! { |a,b| a.score < b.score ? 1 : -1 }
    true
  end

  def find_guild_by_member_name(member_name)
    @guilds.each { |guild|
      guild.members.each { |member|
        return guild if member.name == member_name      
      }
    }
    nil
  end

  def find_member_by_name(member_name)
    @guilds.each { |guild|
      guild.members.each { |member|
        return member if member.name == member_name      
      }
    }
    nil
  end

  def find_outlaw_by_name(name)
    @outlaws.each { |outlaw|
      return outlaw if name == outlaw.name
    }
    nil
  end

  def find_foreigner_by_name(name)
    @foreigners.each { |foreigner|
      return foreigner if name == foreigner.name
    }
    nil
  end

  def find_by_name(name)

    character = find_member_by_name(name)
    character = find_outlaw_by_name(name) if !character
    character = find_foreigner_by_name(name) if !character

    if !character
      character = Character.new(name)
      if !character.request
        puts "Player deleted: #{character.name}"
        return nil
      end

      if character.is_foreigner?(@name)
        @foreigners.push(character)
        puts "Foreigner added: #{character.name} from #{character.world}"
      else
        @outlaws.push(character)
        puts "Outlaw added: #{character.name}"
      end
    end

    character
  end

  def calculate_modifier(percent, param)

    character = (param.class == Character) ? param : find_by_name(param)
    return nil if !character

    raise "Ops #{character.level}" if character.level < 0.0

    base_modifier = percent*character.level.to_f

    guild = find_guild_by_member_name((param.class == Character) ? param.name : param)
    base_modifier += GUILD_PERCENT*guild.base_factor if guild
 
    base_modifier
  end

  def update_social_modifiers!
    @guilds.each { |guild| 
 
      guild.friends = []
      guild.assistances = []
      guild.victims = []
      guild.killers = []

      guild.members.each { |member|

        member.friends.each { |friend_name|
          if guild != find_guild_by_member_name(friend_name)

            next if !(modifier=calculate_modifier(MARRIED_FRIEND_PERCENT, friend_name))
            guild.friends.push(modifier)
          end
        }
      
        @guilds.each { |other_guild|
          if other_guild != guild
            other_guild.members.each { |other_member|
              other_member.killers.each { |other_killer_team|
                if other_killer_team.include?(member.name)

                  modifier = calculate_modifier(VICTIM_PERCENT, other_member)
                  guild.victims.push(modifier)

                  other_killer_team.each { |other_killer_name|
                    if guild != find_guild_by_member_name(other_killer_name)

                      next if !(modifier=calculate_modifier(BATTLE_FRIEND_PERCENT, other_killer_name))
                      guild.assistances.push(modifier)
                    end
                  }
                end
              }
            }
          end
        }

        member.killers.each { |killer_team|

          killers_modifiers = []
          killer_team.each { |killer_name|
            if guild != find_guild_by_member_name(killer_name)

              next if !(modifier=calculate_modifier(KILLER_PERCENT, killer_name))
              killers_modifiers.push(modifier)
            end
          }

          guild.killers.push(killers_modifiers.average) if killers_modifiers != []
        }
      }
    }
    
    true
  end

  def update_social_modifiers_outlaws!

    frozen_outlaws = @outlaws.clone

    @guilds.each { |guild|
      guild.members.each{ |member|

        frozen_outlaws.each { |outlaw|
          outlaw.killers.each { |killer_team|
            if killer_team.include?(member.name)    

              modifier = calculate_modifier(VICTIM_PERCENT, outlaw)
              guild.victims.push(modifier)

              killer_team.each { |battle_mate_name|
                if guild != find_guild_by_member_name(battle_mate_name)
          
                  next if !(modifier=calculate_modifier(BATTLE_FRIEND_PERCENT, battle_mate_name))
                  guild.assistances.push(modifier)
                end
              }
            end
          }
        }
      }
    }

    true
  end

  def update_guild_factors_bounds!
    bounds = {}

    values = @guilds.collect(&:assistances_modifier).sort { |a,b| a < b ? 1 : -1 }
    bounds[:assistances] = { :upper => values.first, :lower => values.last }

    values = @guilds.collect(&:friends_modifier).sort { |a,b| a < b ? 1 : -1 }
    bounds[:friends] = { :upper => values.first, :lower => values.last }

    Guild.const_set(:GUILD_MODIFIERS_BOUNDS, bounds)

    bounds = {}

    values = @guilds.collect(&:base_factor).sort { |a,b| a < b ? 1 : -1 }
    bounds[:base] = { :upper => values.first, :lower => values.last }

    values = @guilds.collect(&:pvp_factor).sort { |a,b| a < b ? 1 : -1 }
    bounds[:pvp] = { :upper => values.first, :lower => values.last }

    values = @guilds.collect(&:social_factor).sort { |a,b| a < b ? 1 : -1 }
    bounds[:social] = { :upper => values.first, :lower => values.last }

    Guild.const_set(:GUILD_FACTORS_BOUNDS, bounds)

    true
  end

  def list
    guilds_list = ""

    guilds_list += "\nGuilds list on #{@name} (Updated: #{Time.now.utc})\n"
    guilds_list += "---------------------------------------\n"

    guild_characters = @guilds.map { |guild| guild.members.length }.sum 
    outlaw_characters = @outlaws.length
    guilds_list += "Guild characters number  #{guild_characters}\n"
    guilds_list += "Outlaw characters number #{outlaw_characters}\n"
    guilds_list += "Total characters number  #{guild_characters+outlaw_characters}\n"
    guilds_list += "---------------------------------------\n"

    modifiers = Guild.const_get(:GUILD_MODIFIERS_BOUNDS)

    guilds_list += "Assistances modifier bounds    [#{modifiers[:assistances][:lower]}, #{modifiers[:assistances][:upper]}]\n"
    guilds_list += "Relatives modifier bounds      [#{modifiers[:friends][:lower]}, #{modifiers[:friends][:upper]}]\n"
    guilds_list += "---------------------------------------\n"

    factors = Guild.const_get(:GUILD_FACTORS_BOUNDS)

    guilds_list += "Base factor bounds      [#{factors[:base][:lower]}, #{factors[:base][:upper]}]\n"
    guilds_list += "PvP factor bounds       [#{factors[:pvp][:lower]}, #{factors[:pvp][:upper]}]\n"
    guilds_list += "Community factor bounds [#{factors[:social][:lower]}, #{factors[:social][:upper]}]\n"
    guilds_list += "---------------------------------------\n"

    @guilds.each_index { |position|
    
      guild = @guilds[position]
      guilds_list += "\nPosition #{position+1}/#{@guilds.length}:" 
      guilds_list += guild.stats
    }
    
    guilds_list
  end

  def results_directory
    "results/#{@name}"
  end

  def results_directory_html
    "#{results_directory}/html"
  end

  def dump
    FileUtils.makedirs(results_directory) if !File.exists?(results_directory)

    file = File.open("#{results_directory}/list.txt", "w")
    file.write(list)
    file.close
  end

  def dump_to_html_row(html_file, row)
    html_file.write("<tr>\n")
    row.each { |column|
      html_file.write("	<th>#{column}</th>\n")
    }
    html_file.write("</tr>\n")
  end

  def dump_to_html_table(html_file)
    row = []
    row.push("position")
    row.push("name")
    row.push("members")
    row.push("total level")
    row.push("highest level")
    row.push("median level")
    row.push("lowest level")
    row.push("average level")
    row.push("deads")
    row.push("kills")
    row.push("assistances")
    row.push("relatives")
    row.push("base factor")
    row.push("pvp factor")
    row.push("community factor")
    row.push("overall score")

    dump_to_html_row(html_file, row)
    
    @guilds.each_index { |index|
      guild = @guilds[index]

      row = []
      row.push(index+1)
      row.push(guild.name)
      row.push(guild.size)
      row.push(guild.total)
      row.push(guild.strongest.level)
      row.push(guild.median.level)
      row.push(guild.weakest.level)
      row.push(guild.average)
      row.push(guild.killers.length)
      row.push(guild.victims.length)
      row.push(guild.assistances.length)
      row.push(guild.friends.length)
      row.push(guild.normalized_base_factor)
      row.push(guild.normalized_pvp_factor)
      row.push(guild.normalized_social_factor)
      row.push(guild.score)

      dump_to_html_row(html_file, row)
    }
  end

  def dump_to_html
    FileUtils.makedirs(results_directory_html) if !File.exists?(results_directory_html)

    javascript_code = File.open("html/sorttable.js")
    results_javascript_code = File.new("#{results_directory_html}/sorttable.js", "w")
    results_javascript_code.write(javascript_code.read)
    results_javascript_code.close
    javascript_code.close

    css_file = File.open("html/example.css")
    results_css_file = File.new("#{results_directory_html}/example.css", "w")
    results_css_file.write(css_file.read)
    results_css_file.close
    css_file.close

    basic_html = File.open("html/empty.html")
    results_html = File.new("#{results_directory_html}/#{@name}.html", "w")

    basic_html.each { |line|

      line.gsub!("replace", "#{@name}'s guilds ranking") if line.match("<title")
      results_html.write("#{line}")
      dump_to_html_table(results_html) if line.match("<table")
    }

    results_html.close
    basic_html.close
  end

end

