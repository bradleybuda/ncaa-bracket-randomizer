require 'rubygems'
require 'pp'
require 'yajl'

bracket = File.open("2010teams.json") { |f| Yajl::Parser.parse(f) }

team_regex = /\s*(\d+) <a href="[^"]+">([^<]+)<\/a>\s*<a href=.*?<\/a><\/a>\s*(\d+-\d+)\s*(\.\d+)\s*([\d.]*)\/(\d+)\s*([\d.]*)\/(\d+)/

kenpom = File.readlines('pom2010.html').map do |l|
  if l =~ team_regex
    Hash[[:rank, :name, :record, :pythagorean, :adjusted_offense, :adjusted_offense_rank, :adjusted_defence, :adjusted_defense_rank].zip($~.captures)]
  else
    nil
  end
end.compact

# make sure we agree on all our team names and build a structure
# {"region" -> {seed -> [name, pyth, adjo, adjd]}}
merged = {}
bracket.each do |region, seeds|
  merged[region] = {}
  
  seeds.each do |seed, teams|
    teams = [teams] unless teams.kind_of? Array
    teams.each_with_index do |team, i|
      team_kenpom = kenpom.find { |k| k[:name] == team }
      raise "Can't find kenpom for #{team}" if team_kenpom.nil?
      
      merged[region][seed.to_i + i] = team_kenpom # treating the second team in the play-in as a 17 seed
    end
  end
end

class Game
  attr_reader :round, :region
  attr_accessor :child
  
  def initialize(options)
    @region = options[:region]
    @round = options[:round]
    @game_number = options[:game_number]
    @seed_one = options[:seed_one]
    @team_one = options[:team_one] || {}
    @seed_two = options[:seed_two]
    @team_two = options[:team_two] || {}
    @child = nil
  end

  def inspect
    "#{@team_one[:name]} vs #{@team_two[:name]} round #{@round} game #{@game_number} region #{@region}"
  end
end

games = []
next_game_number = 1

# First round games
merged.each do |region, bracket|
  [1, 8, 5, 4, 6, 3, 7, 2].each do |seed|
    opponent_seed = 17 - seed
    team_one = bracket[seed]
    team_two = bracket[opponent_seed]
    games << Game.new(:region => region, :round => 1, :game_number => next_game_number, :seed_one => seed, :team_one => team_one, :seed_two => opponent_seed, :team_two => team_two)
    next_game_number += 1
  end
end

# Subsequent regional rounds
[2, 3, 4].each do |round|
  previous_round_games = games.find_all { |g| g.round == round - 1 }
  previous_round_games.each_slice(2) do |game_one, game_two|
    game = Game.new(:region => game_one.region, :round => round, :game_number => next_game_number)
    game_one.child = game_two.child = game
    next_game_number += 1

    games << game
  end
end

# Final Four
semifinals = [%w(Midwest West), %w(East South)].map do |region_pairing|
  semifinal = Game.new(:region => 'Final Four', :round => 5, :game_number => next_game_number)
  regional_finals = region_pairing.map { |region| games.find { |g| g.region == region && g.round == 4 } }
  regional_finals.each { |rf| rf.child = semifinal }
  next_game_number += 1
  games << semifinal
  semifinal
end

championship = Game.new(:region => 'Final Four', :round => 6, :game_number => next_game_number)
semifinals.each { |sf| sf.child = championship }
games << championship

winner = Game.new(:region => 'Final Four', :round => 7, :game_number => next_game_number + 1)
championship.child = winner
games << winner

pp games
