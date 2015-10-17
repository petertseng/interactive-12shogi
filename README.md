# Interactive 12 shogi

This interacts with http://dell.tanaka.ecc.u-tokyo.ac.jp/~ktanaka/dobutsushogi/ to play an interactive game of [Dōbutsu shōgi (どうぶつしょうぎ)](https://en.wikipedia.org/wiki/D%C5%8Dbutsu_sh%C5%8Dgi), variously known as:

* Twelve Janggi (십이장기)
* Let's Catch the Lion!

# Setup

Download http://dell.tanaka.ecc.u-tokyo.ac.jp/~ktanaka/dobutsushogi/dobutsu-src-20150109.tar.gz, invoke `make checkState` to get a `checkState` binary (you could invoke `make` to get all the binaries, but that is not necessary).
Move the `checkState` binary to the current working directory (or edit the `EXECUTABLE` constant inside `interactive-12shogi.rb`).
Download http://dell.tanaka.ecc.u-tokyo.ac.jp/~ktanaka/dobutsushogi/dobutsu-dat.tar.gz, unpack at least the following three files into the current working directory as well:

* allstates.dat
* winLoss.dat
* winLossCount.dat

(In general these are just the files that `checkState.cc` lists)

# Usage

Run `interactive-12shogi.rb [first_player_name] [second_player_name] [red|green]`.
All arguments are optional (the third argument indicates whether the first player is red or green).

This opens an interactive prompt to step through the game.
At each step, the possible moves of the active player are listed,
along with the game outcome under optimal play by both players.
Possible commands are:

* "undo": Undo the most recent move. (Yes, you may undo multiple times if desired)
* "history": Print out all moves made in this game and the theoretical game outcome at each move.
* "cw": Rotate board clockwise.
* "ccw": Rotate board counterclockwise.
* "flip": Rotate board 180 degrees.
* (A number): Perform the move labeled with that number.

An example of what it looks like:

```
First Player

　　４　　３　　２　　１
　＋－－＋－－＋－－＋－－＋
Ａ｜相＞｜　　｜　　｜＜將｜Ａ
　＋－－＋－－＋－－＋－－＋
Ｂ｜王＞｜子＞｜＜子｜＜王｜Ｂ
　＋－－＋－－＋－－＋－－＋
Ｃ｜將＞｜　　｜　　｜＜相｜Ｃ
　＋－－＋－－＋－－＋－－＋
　　４　　３　　２　　１
　　　　　　　　Second Player
　　　　　　　　　
It's First Player's turn

 0: 將 C4 - C3 lose (Second Player wins) in  76 moves
 1: 王 B4 - C3 lose (Second Player wins) in  76 moves
 2: 子 B3 x B2 lose (Second Player wins) in  74 moves
 3: 王 B4 - A3 lose (Second Player wins) in  76 moves
What move should First Player make?
```
