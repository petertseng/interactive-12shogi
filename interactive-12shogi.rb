require 'open3'
require 'tempfile'

EXECUTABLE = './checkState'
raise "expected #{EXECUTABLE} to exist, but it doesn't" unless File.exist?(EXECUTABLE)

PLAYER_COMPUTER_NAMES = {
  1 => '+',
  -1 => '-',
}

PIECE_NAMES = {
  chick: '子',
  hen: '侯',
  giraffe: '將',
  elephant: '相',
  lion: '王',
}

PIECE_COMPUTER_NAMES = {
  chick: 'HI',
  hen: 'NI',
  giraffe: 'KI',
  elephant: 'ZO',
  lion: 'LI',
}

[PLAYER_COMPUTER_NAMES, PIECE_NAMES, PIECE_COMPUTER_NAMES].each { |h|
  h.values.each(&:freeze)
  h.freeze
}

PIECE_SYMBOLS = PIECE_COMPUTER_NAMES.invert

def colorize(str, color)
  "\e[1;#{color}m#{str}\e[0m"
end

Piece = Struct.new(:player, :type)

class Game
  def initialize(p1_name: 'First Player', p2_name: 'Second Player', p1_color: 'green', p2_color: 'red')
    @player_names = {
      1 => p1_name.freeze,
      -1 => p2_name.freeze,
    }.freeze
    @player_colors = {
      1 => self.class.interpret_color(p1_color),
      -1 => self.class.interpret_color(p2_color),
    }.freeze

    @board = [
      [Piece.new(-1, :giraffe), Piece.new(-1, :lion), Piece.new(-1, :elephant)],
      [nil, Piece.new(-1, :chick), nil],
      [nil, Piece.new(1, :chick), nil],
      [Piece.new(1, :elephant), Piece.new(1, :lion), Piece.new(1, :giraffe)],
    ]

    @reserves = {
      1 => {
        chick: 0,
        elephant: 0,
        giraffe: 0,
      },
      -1 => {
        chick: 0,
        elephant: 0,
        giraffe: 0,
      },
    }

    @player_to_move = 1

    @undo_log = []
  end

  def self.interpret_color(c)
    case c.downcase
    when 'red'; 31
    when 'green'; 32
    else; raise "Unknown color #{c}"
    end
  end

  def self.interpret_coord(coord)
    return [nil, nil] if coord == '00'
    three_side = coord[0].ord - ?A.ord
    four_side = coord[1].to_i - 1
    [three_side, four_side]
  end

  def history
    @undo_log.map { |move, _| move }
  end

  def apply_move(move)
    three_side_new, four_side_new = self.class.interpret_coord(move.destination_square)
    if move.source_square == '00'
      # It's a drop
      old_piece = @board[four_side_new][three_side_new]
      raise "#{@player_to_move} #{move} dropped onto a #{old_piece}" if old_piece

      old_count = @reserves.fetch(@player_to_move).fetch(move.piece)
      raise "#{@player_to_move} #{move} dropped nonexistent #{move.piece}" unless old_count > 0
      @reserves.fetch(@player_to_move)[move.piece] = old_count - 1

      @undo_log << [move, {
        type: :drop,
        four_side_new: four_side_new,
        three_side_new: three_side_new,
        piece: move.piece,
      }]
    else
      # It's a move
      three_side_old, four_side_old = self.class.interpret_coord(move.source_square)
      old_piece = @board[four_side_old][three_side_old]

      promoting = move.piece == :hen && old_piece.type == :chick
      raise "#{@player_to_move} #{move} moved an #{old_piece}, expected #{move.piece}" unless move.piece == old_piece.type || promoting

      captured_piece = @board[four_side_new][three_side_new]
      @reserves.fetch(@player_to_move)[captured_piece.type] += 1 if captured_piece

      @board[four_side_old][three_side_old] = nil

      @undo_log << [move, {
        type: :move,
        four_side_old: four_side_old,
        three_side_old: three_side_old,
        four_side_new: four_side_new,
        three_side_new: three_side_new,
        piece: old_piece.type,
        captured_piece: captured_piece && captured_piece.type
      }]
    end
    @board[four_side_new][three_side_new] = Piece.new(@player_to_move, move.piece)
    @player_to_move *= -1
  end

  def undo_move
    @player_to_move *= -1

    _, move = @undo_log.pop
    return unless move
    case move[:type]
    when :move
      # Put the piece back on the square where it came from.
      # Unpromote it if it promoted.
      @board[move[:four_side_old]][move[:three_side_old]] = Piece.new(@player_to_move, move[:piece])

      if move[:captured_piece]
        # Remove the captured piece from the player's reserves.
        old_count = @reserves.fetch(@player_to_move).fetch(move[:captured_piece])
        raise "#{@player_to_move} #{move} undid capture of nonexistent #{move[:captured_piece]}" unless old_count > 0
        @reserves.fetch(@player_to_move)[move[:captured_piece]] = old_count - 1
        # Put the captured piece back on the board, on the opponent's side.
        @board[move[:four_side_new]][move[:three_side_new]] = Piece.new(-@player_to_move, move[:captured_piece])
      else
        # If no captured piece, just clear the square the piece moved to.
        @board[move[:four_side_new]][move[:three_side_new]] = nil
      end
    when :drop
      # Return the dropped piece to reserves, remove it from the board.
      @reserves.fetch(@player_to_move)[move[:piece]] += 1
      @board[move[:four_side_new]][move[:three_side_new]] = nil
    else
      raise "Unknown move type #{move[:type]}"
    end
  end

  def player_name(id, colorize: true)
    name = @player_names.fetch(id)
    return name unless colorize
    colorize(name, player_color(id))
  end

  def player_color(id = nil)
    @player_colors.fetch(id || @player_to_move)
  end

  def player_to_move
    player_name(@player_to_move)
  end

  def player_not_to_move
    player_name(-@player_to_move)
  end

  def reserve_string(id)
    pieces = @reserves.fetch(id).map { |sym, num| PIECE_NAMES.fetch(sym) * num }.join
    colorize(pieces, player_color(id))
  end

  def write_to_file(filename)
    self.class.write_to_file(filename, @board, @reserves, @player_to_move)
  end

  def self.write_to_file(filename, board, reserves, player_to_move)
    File.open(filename, ?w) { |file|
      board.each { |row|
        row.each { |piece|
          if piece
            file.write(PLAYER_COMPUTER_NAMES.fetch(piece.player))
            file.write(PIECE_COMPUTER_NAMES.fetch(piece.type))
          else
            file.write(' . ')
          end
        }
        file.puts
      }
      [1, -1].each { |player_id|
        player_reserve = reserves[player_id]
        file.write(player_reserve[:chick])
        file.write(player_reserve[:elephant])
        file.write(player_reserve[:giraffe])
      }
      file.puts
      file.puts(PLAYER_COMPUTER_NAMES.fetch(player_to_move))
    }
  end

  def to_s(colors: true, first_player_position: :down)
    case first_player_position
    when :up
      display = @board.reverse.map(&:reverse)
      rows = '4321'
      cols = 'CBA'
    when :down
      display = @board
      rows = '1234'
      cols = 'ABC'
    when :left
      display = @board.reverse.transpose
      rows = 'ABC'
      cols = '4321'
    when :right
      display = @board.transpose.reverse
      rows = 'CBA'
      cols = '1234'
    else raise "unsupported orientation #{first_player_position}"
    end
    rows = rows.split(//)
    cols = cols.split(//)

    str = ''

    case first_player_position
    when :up
      str <<  "#{player_name(1)} #{reserve_string(1)}\n"
    when :down
      str <<  "#{player_name(-1)} #{reserve_string(-1)}\n"
    when :left
      str << "#{player_name(1)}\n"
      str << "#{reserve_string(1)}\n"
    when :right
      str << "#{player_name(-1)}\n"
      str << "#{reserve_string(-1)}\n"
    end

    # Table top
    str << "    #{cols.join('   ')}\n"
    str <<  "  ┏#{'━━━┳' * (cols.size - 1)}━━━┓\n"

    # Table body
    str << display.zip(rows).map { |row, row_id|
      pieces = row.map { |piece|
        next '   ' unless piece
        name = PIECE_NAMES.fetch(piece.type).dup

        case first_player_position
        when :up
          name << (piece.player == 1 ? ?V : ?^)
        when :down
          name << (piece.player == 1 ? ?^ : ?V)
        when :left
          if piece.player == 1
            name << ?>
          else
            name = ?< + name
          end
        when :right
          if piece.player == 1
            name = ?< + name
          else
            name << ?>
          end
        end

        color = player_color(piece.player)
        colorize(name, color)
      }
      "#{row_id} ┃#{pieces.join('┃')}┃ #{row_id}\n"
    }.join("  ┣#{'━━━╋' * (cols.size - 1)}━━━┫\n")

    # Table bottom
    str << "  ┗#{'━━━┻' * (cols.size - 1)}━━━┛\n"
    str << "    #{cols.join('   ')}\n"

    case first_player_position
    when :up
      str <<  "#{player_name(-1)} #{reserve_string(-1)}\n"
    when :down
      str <<  "#{player_name(1)} #{reserve_string(1)}\n"
    when :left
      pad = ' ' * (3 + cols.size * 4 + 2 - @player_names[-1].length)
      str <<  "#{pad}#{player_name(-1)}\n"
      str <<  "#{pad}#{reserve_string(-1)}\n"
    when :right
      pad = ' ' * (3 + cols.size * 4 + 2 - @player_names[1].length)
      str <<  "#{pad}#{player_name(1)}\n"
      str <<  "#{pad}#{reserve_string(1)}\n"
    end
    str << "It's #{player_to_move}'s turn"

    str
  end
end

class Move
  attr_reader :move_id, :result, :moves
  attr_reader :source_square, :destination_square
  attr_reader :piece
  def initialize(text)
    @text = text
    move_id, rest = text.split(?:)
    @move_id = move_id.to_i
    squares_and_piece, result = rest.split
    result_pieces = result.split(?()
    winner = result_pieces[0].to_i
    @moves = result_pieces[1].to_i

    # I'm totally unsure about the 1, -1 here but it looks right...
    # I'm reading it as "My opponent's best response"
    # If my opponent's best response to X is to lose in Y moves:
    # then I will win in Y+1 moves if I play X.
    # IF my opponent's best response to X is to win in Y moves:
    # then I will lose in Y+1 moves if I play X.
    if winner == 0
      raise "#{line} has bad winner" unless result_pieces[0] == ?0
      @result = :draw
    elsif winner == 1
      @result = :lose
    elsif winner == -1
      @result = :win
    end
    @source_square = squares_and_piece[1..2].freeze
    @destination_square = squares_and_piece[3..4].freeze
    @piece = PIECE_SYMBOLS.fetch(squares_and_piece[5..6])
  end

  def to_s(id: true, color: nil, my_name: nil, opponents_name: nil)
    result2 = ''
    max_length = [my_name.to_s.length, opponents_name.to_s.length].max
    if @result == :lose && opponents_name
      result2 = " (%#{max_length}s wins)" % opponents_name
    elsif @result == :win && my_name
      result2 = " (%#{max_length}s wins)" % my_name
    end
    piece = PIECE_NAMES.fetch(@piece)
    "#{('%2d: ' % @move_id) if id}%s %2s -> %2s %4s%s in %3d moves" % [
      color ? colorize(piece, color) : piece,
      @source_square, @destination_square,
      @result, result2, @moves
    ]
  end
end

if ARGV.include?('-h')
  puts "usage: #{$PROGRAM_NAME} p1 p2 p1_color"
  Kernel.exit(0)
end

class GameRunner
  def initialize(game)
    @game = game
    @first_player_position = :down
    @possible_moves = []
    @filename = Tempfile.new('12janggi').path
  end

  def output_moves
    color = @game.player_color
    puts @possible_moves.map { |move| move.to_s(
      my_name: @game.player_to_move,
      opponents_name: @game.player_not_to_move,
      color: color,
    )}
  end

  def change_direction(change)
    @first_player_position = change[@first_player_position]
    puts @game.to_s(first_player_position: @first_player_position)
    puts
    output_moves
  end

  def run
    @game.write_to_file(@filename)
    puts 'Current board:'
    puts @game.to_s(first_player_position: @first_player_position)
    puts

    begin
      @possible_moves = get_moves
    rescue => e
      puts e.inspect
      if File.exist?(@filename)
        puts IO.read(@filename)
      else
        puts 'tmp file got deleted somehow?'
      end
      puts 'retrying?'
      return
    end

    output_moves

    move_id = nil
    until (0...(@possible_moves.size)).include?(move_id)
      print("What move should #{@game.player_to_move} make? ")
      raw = $stdin.gets.chomp.downcase

      if raw == 'undo'
        @game.undo_move
        return
      elsif raw == 'history'
        player_names = [1, -1].map { |i| [i, @game.player_name(i)] }.to_h
        @game.history.each_with_index { |history_move, i|
          player_id = i % 2 == 0 ? 1 : -1
          color = @game.player_color(player_id)
          max_length = player_names.values.map(&:length).max
          puts ("%2d. %#{max_length}s " % [i + 1, player_names[player_id]]) + history_move.to_s(
            id: false,
            my_name: player_names[player_id],
            opponents_name: player_names[-player_id],
            color: color,
          )
        }
        return
      elsif raw == 'flip'
        change_direction(up: :down, down: :up, left: :right, right: :left)
      elsif raw == 'cw'
        change_direction(up: :right, down: :left, left: :up, right: :down)
      elsif raw == 'ccw'
        change_direction(up: :left, down: :right, left: :down, right: :up)
      elsif raw.to_i.to_s == raw.chomp
        move_id = raw.to_i
      end
    end

    move = @possible_moves[move_id]
    @game.apply_move(move)
  end

  def get_moves
    Open3.popen2e(EXECUTABLE, @filename) { |input, output, wait|
      input.close

      # Discard one line of all dashes
      line = output.readline.chomp
      raise "#{line} was not all dashes" unless line.each_char.all? { |c| c == ?- }

      # Discard four lines of board
      4.times { output.readline }

      # Discard one line of reserve pieces
      line = output.readline.chomp
      raise "#{line} was not six chars" unless line.size == 6

      # Discard one line of player to move
      line = output.readline.chomp
      raise "#{line} was not + or -" unless line == ?+ || line == ?-

      # Discard one empty line
      line = output.readline.chomp
      raise "#{line} was non empty" unless line.empty?

      # Who wins?
      line = output.readline.chomp.split(?()
      winner = line[0].to_i
      moves = line[1].to_i

      if winner == 0
        raise "#{line} has bad winner" unless line[0] == ?0
        puts 'Game status: Drawn'
      else
        puts "Game status: #{@game.player_name(winner)} wins in #{moves} moves"
      end
      puts

      moves = []

      output.each { |l|
        if l.start_with?('Move :')
          output.close
          return moves
        end
        moves << Move.new(l)
      }

      # If we got here, moves is empty.
      moves
    }
  end
end

game = Game.new(
  p1_name: ARGV[0] || 'First Player',
  p2_name: ARGV[1] || 'Second Player',
  p1_color: ARGV[2] == 'red' ? 'red' : 'green',
  p2_color: ARGV[2] == 'red' ? 'green' : 'red',
)

runner = GameRunner.new(game)
loop { runner.run }
