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

require 'net/http'
require 'uri'
require 'fileutils'
require 'iconv'

TIBIA_CHAR_URL = "http://www.tibia.com/community/?subtopic=characters&name="
TIBIA_GUILD_URL = "http://www.tibia.com/community/?subtopic=guilds&page=view&GuildName="
TIBIA_WORLD_URL = "http://www.tibia.com/community/?subtopic=guilds&world="

TIME_TO_WAIT = 0.5

class Content

  def initialize(content_type, name)
    @content = nil
    @content_type = content_type
    @name = name
  end

  def clean(raw_content)
    return Iconv.new('UTF-8//IGNORE', 'UTF-8').iconv(raw_content)
  end

  def content_directory
    "cache/#{@content_type}/"    
  end

  def content_path
    "cache/#{@content_type}/#{@name}"
  end

  def content_url
    url_name = @name.gsub(" ", "+").strip

    case @content_type
      when :character 
        TIBIA_CHAR_URL+url_name
      when :guild
        TIBIA_GUILD_URL+url_name
      when :world
        TIBIA_WORLD_URL+url_name
    end
  end

  def try_cache
    File.exists?(content_path) ? clean(File.open(content_path).read) : nil 
  end

  def save_to_cache
    FileUtils.makedirs(content_directory) if !File.exists?(content_directory)    

    file = File.new(content_path, "w")
    file.write(clean(@content))
    file.close
  end

  def get!

    content_from_cache = try_cache
    return content_from_cache if content_from_cache

    url = content_url
    attempts = 0

    sleep(TIME_TO_WAIT)

    while !@content

      begin
        attempts += 1
        raw_content = Net::HTTP.get URI.parse(url)
        @content = clean(raw_content)       
        save_to_cache
      rescue SignalException, StandardError
        puts "Failed on attempt #{attempts} getting #{url}"
        sleep(2*TIME_TO_WAIT)
      end
    end

    @content
  end

end

