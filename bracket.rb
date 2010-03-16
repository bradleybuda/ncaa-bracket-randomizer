require 'rubygems'
require 'active_support'
require 'pp'
require 'yajl'

class Team
  attr_reader :name, :pythagorean
  attr_accessor :seed
  
  def initialize(options)
    @name = options[:name]
    @pythagorean = options[:pythagorean].to_f
    @seed = nil
  end

  def chance_of_win_over(other)
    # log5: http://www.diamond-mind.com/articles/playoff2002.htm
    
    a = self.pythagorean
    b = other.pythagorean
    (a - a * b) / (a + b - 2 * a * b)
  end

  def inspect
    "<#{@name} pyth=#{@pythagorean}>"
  end
end

class Game
  extend ActiveSupport::Memoizable
  
  attr_reader :round, :region, :feeder_games, :team_one, :team_two, :game_number
  
  def winner_advances_to=(game)
    @winner_advances_to = game
    game.feeder_games << self
    game
  end
  
  def initialize(options)
    @region = options[:region]
    @round = options[:round]
    @game_number = options[:game_number]
    @seed_one = options[:seed_one]
    @team_one = options[:team_one]
    @seed_two = options[:seed_two]
    @team_two = options[:team_two]
    @feeder_games = []
  end
  
  def outcomes
    if round == 1
      # base case
      p = @team_one.chance_of_win_over(@team_two)
      [
       Outcome.new(:game => self, :winner => @team_one, :probability => p),
       Outcome.new(:game => self, :winner => @team_two, :probability => 1.0 - p),
      ]
      
    else
      # recursive case
      team_one_candidates, team_two_candidates = feeder_games.map(&:outcomes)
      
      results = []
      
      team_one_candidates.each do |team_one_outcome|
        # liklihood that team will win this round is the liklihood
        # that it reached the round times the liklihood that any
        # particular opponent reached this round times the liklihood
        # of a win over that particular opponent, summed over every
        # possible opponent

        p = team_two_candidates.map do |team_two_outcome|
          team_one_outcome.probability * team_two_outcome.probability * team_one_outcome.winner.chance_of_win_over(team_two_outcome.winner)
        end.sum
        
        results << Outcome.new(:game => self, :winner => team_one_outcome.winner, :probability => p)
      end

      # likewise for p2
      team_two_candidates.each do |team_two_outcome|
        p = team_one_candidates.map do |team_one_outcome|
          team_two_outcome.probability * team_one_outcome.probability * team_two_outcome.winner.chance_of_win_over(team_one_outcome.winner)
        end.sum

        results << Outcome.new(:game => self, :winner => team_two_outcome.winner, :probability => p)
      end

      results
    end
  end
  memoize :outcomes
  
  def inspect
    "#{@region} region, Round #{@round}, Game #{@game_number}"
  end
end

class Outcome
  attr_reader :game, :winner, :probability
  
  def initialize(options)
    @game = options[:game]
    @winner = options[:winner]
    @probability = options[:probability]
  end

  # points under TS CBS scoring system
  def points
    points_by_round = [nil, 3, 5, 8, 13, 21, 34]
    points_by_round[@game.round] + @winner.seed
  end

  def expected_points
    points.to_f * @probability
  end
  
  def prerequisites
    if @game.round == 1
      []
    else
      required_outcome = @game.feeder_games.map(&:outcomes).flatten.find { |o| o.winner == @winner }
      [required_outcome] + required_outcome.prerequisites
    end
  end

  def inspect
    "#{@winner.name} wins ##{@game.game_number} (round #{@game.round}); p = #{'%.3f' % @probability}, score = #{points}, E(score) = #{expected_points}"
  end
end

### main ###

bracket = File.open("2010teams.json") { |f| Yajl::Parser.parse(f) }

team_regex = /\s*(\d+) <a href="[^"]+">([^<]+)<\/a>\s*<a href=.*?<\/a><\/a>\s*(\d+-\d+)\s*(\.\d+)\s*([\d.]*)\/(\d+)\s*([\d.]*)\/(\d+)/

kenpom = File.readlines('pom2010.html').map do |l|
  if l =~ team_regex
    Team.new(Hash[[:rank, :name, :record, :pythagorean, :adjusted_offense, :adjusted_offense_rank, :adjusted_defence, :adjusted_defense_rank].zip($~.captures)])
  else
    nil
  end
end.compact

# make sure we agree on all our team names and build a structure
# {"region" -> {seed -> Team}}
merged = {}
bracket.each do |region, seeds|
  merged[region] = {}
  
  seeds.each do |seed, teams|
    teams = [teams] unless teams.kind_of? Array
    teams.each_with_index do |team, i|
      team_kenpom = kenpom.find { |t| t.name == team }
      raise "Can't find kenpom for #{team}" if team_kenpom.nil?

      team_kenpom.seed = seed.to_i + i # treating the second team in the play-in as a 17 seed b/c the original author did
      merged[region][team_kenpom.seed] = team_kenpom
    end
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
    game_one.winner_advances_to = game_two.winner_advances_to = game
    next_game_number += 1

    games << game
  end
end

# Final Four
semifinals = [%w(Midwest West), %w(East South)].map do |region_pairing|
  semifinal = Game.new(:region => 'Final Four', :round => 5, :game_number => next_game_number)
  regional_finals = region_pairing.map { |region| games.find { |g| g.region == region && g.round == 4 } }
  regional_finals.each { |rf| rf.winner_advances_to = semifinal }
  next_game_number += 1
  games << semifinal
  semifinal
end

championship = Game.new(:region => 'Final Four', :round => 6, :game_number => next_game_number)
semifinals.each { |sf| sf.winner_advances_to = championship }
games << championship

possible_outcomes = games.map { |g| g.outcomes }.flatten

# greedily pick outcomes by expected value
picked_outcomes = []

until possible_outcomes.empty?
  next_pick = possible_outcomes.max_by(&:expected_points)
  possible_outcomes -= [next_pick] # either we're going to pick this or discard it
  
  # make sure neither the pick nor its prerequisites conflict with picks already made for other teams
  prerequisite_outcomes = next_pick.prerequisites
  if ([next_pick] + prerequisite_outcomes).any? { |prereq| picked_outcomes.any? { |picked| picked.game == prereq.game && picked.winner != prereq.winner } }
    STDOUT.puts "discarding '#{next_pick.inspect}' because it is in conflict with another pick"
    next
  end
  
  # pick the outcome and its prereqs
  # TODO some of these prereqs are getting picked twice; that's okay, we'll uniq them out at the end
  possible_outcomes -= prerequisite_outcomes
  picked_outcomes += [next_pick] + prerequisite_outcomes
  STDOUT.puts "picked #{next_pick.inspect} and #{prerequisite_outcomes.size} prerequisites"

  # TODO can be smarter about pruning impossible outcomes here; we'll
  # need to do this if we ever implement more interesting search
  # strategies
end

picks = picked_outcomes.uniq

pp picks
puts "expected points: #{picks.map(&:expected_points).sum}"
