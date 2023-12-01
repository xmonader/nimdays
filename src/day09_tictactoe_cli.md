# Day 9: Tic tac toe

Who didn't play [Tic tac toe](https://en.wikipedia.org/wiki/Tic-tac-toe) with his friends? :)

## What to expect
Today we will implement the Tic tac toe game in Nim, with two modes:
- Human vs Human
- Human vs AI

## Implementation
So, let's get it. The winner in the game is the first player to get three same cells on the board in the same column, row or diagonal.


### imports
```Nimrod
import std/[sequtils, tables, strutils, strformat, random, os, parseopt2]

randomize()
```

### Constraints and objects

We should keep track of the current or the next player.

```
let NEXT_PLAYER = {"X":"O", "O":"X"}.toTable
```

Here we use a table to tell us who is the next player.

#### Board

```Nimrod
type
  Board = ref object of RootObj
    cells: seq[string]
```

Here we define a simple class representing the board
- we use a sequence to represent the cells of the board
- please note cells is just a sequence of elements `0 1 2 3 4 5 6 7 8` but we may visualize it instead as:

```
0 1 2
3 4 5
6 7 9
```
a 2d array for the sake of simplicity.


```Nimrod
let WINS = @[ @[0,1,2], @[3,4,5], @[6,7,8], @[0, 3, 6], @[1,4,7], @[2,5,8], @[0,4,8], @[2,4,6] ]
```

We talked `WIN` patterns cells in the same row or the same column or in same diagonal

```Nimrod
proc newBoard(): Board =
  var b = Board()
  b.cells = @["0", "1", "2", "3", "4", "5", "6", "7", "8"]
  return b
```

The board's initializer sets the values of each cell to the string representation of the cell's index.

##### Winning

```Nimrod
proc done(this: Board): (bool, string) =
    for w in WINS:
        if this.cells[w[0]] == this.cells[w[1]] and this.cells[w[1]]  == this.cells[w[2]]:
          if this.cells[w[0]] == "X":
            return (true, "X")
          elif this.cells[w[0]] == "O":
            return (true, "O")
    if all(this.cells, proc(x:string):bool = x in @["O", "X"]) == true:
        return (true, "tie")
    else:
        return (false, "going")
```

Here we check for the state of the game and the winner is declared if all of the items in one `WIN` patterns are the same. We wait the board to be filled before declaring a draw.

```Nimrod
proc `$`(this:Board): string =
  let rows: seq[seq[string]] = @[this.cells[0..2], this.cells[3..5], this.cells[6..8]]
  for row  in rows:
    for cell in row:
      stdout.write(cell & " | ")
    echo("\n--------------")
```
Since we have the string representation of the board, we can show it as 3x3 grid in a lovely way!

```Nimrod
proc emptySpots(this:Board):seq[int] =
    var emptyindices = newSeq[int]()
    for i in this.cells:
      if i.isDigit():
        emptyindices.add(parseInt(i))
    return emptyindices
```

Here we have a simple helper function that returns the empty spots indices `the spots that doesn't have X or O in it`, remember all the cells are initialized to the string representation of their indices.

#### Game

```Nimrod
type
  Game = ref object of RootObj
    currentPlayer*: string
    board*: Board
    aiPlayer*: string
    difficulty*: int


proc newGame(aiPlayer:string="", difficulty:int=9): Game =
  var
    game = new Game

  game.board = newBoard()
  game.currentPlayer = "X"
  game.aiPlayer = aiPlayer
  game.difficulty = difficulty

  return game
        # 0 1 2
        # 3 4 5
        # 6 7 8
```

Here we have another object representing the game, the players, the difficulty and whether an AI is playing. It also tracks the current player.

- difficulty is only logical in case of AI, it means when does the AI start calculating moves and considering scenarios, 9 being the hardest while 0 is the easiest.

```Nimrod
proc changePlayer(this:Game) : void =
  this.currentPlayer = NEXT_PLAYER[this.currentPlayer]
```
Simple procedure to switch turns between players.

#### Start the game
```Nimrod

proc startGame*(this:Game): void=
    while true:
        echo this.board
        if this.aiPlayer != this.currentPlayer:
          stdout.write("Enter move: ")
          let move = stdin.readLine()
          this.board.cells[parseInt($move)] = this.currentPlayer
        this.change_player()
        let (done, winner) = this.board.done()

        if done == true:
          echo this.board
          if winner == "tie":
              echo("TIE")
          else:
              echo("WINNER IS :", winner )
          break

```

Here, either we have an `aiPlayer` or a game with two humans switching turns and checking for the winner after each move.

### Minmax and AI support
[Minmax](https://en.wikipedia.org/wiki/Minimax) is an algorithm mainly used to predict the possible moves in the future and how to minimize the losses and maximize the chances of winning

- https://www.youtube.com/watch?v=6ELUvkSkCts
- https://www.youtube.com/watch?v=CwziaVrM_vc&t=1199s


```Nimrod

type
  Move = tuple[score:int, idx:int]
```

We need a type Move on a certain idx to represent if it's a good/bad move `depending on the score`

- good means minimizing chances of the human to win or making AI win => high score +10
- bad  means maximizing chances of the human to win or making AI lose => low score -10

So let's say we are in this situation:
```
O X X
X 4 5
X O O
```
And it's `AI turn` we have two possible moves (4 or 5)

```
O X X
X 4 O
X O O
```

this move (to 5) is clearly wrong because the next move to human will allow him to complete the diagonal (2, 4, 6) So this is a bad move we give it score -10
or

```
O X X
X O 5
X O O
```
this move (to 4) minimizes the losses (leads to a TIE instead of making human wins) so we give it a higher score

```Nimrod
proc getBestMove(this: Game, board: Board, player:string): Move =
        let (done, winner) = board.done()
        # determine the score of the move by checking where does it lead to a win or loss.
        if done == true:
            if winner ==  this.aiPlayer:
                return (score:10, idx:0)
            elif winner != "tie": #human
                return (score:(-10), idx:0)
            else:
                return (score:0, idx:0)

        let empty_spots = board.empty_spots()
        var moves = newSeq[Move]()
        for idx in empty_spots:
            # we calculate more new trees depending on the current situation and see where the upcoming moves lead
            var newboard = newBoard()

            newboard.cells = map(board.cells, proc(x:string):string=x)
            newboard.cells[idx] = player
            let score = this.getBestMove(newboard, NEXT_PLAYER[player]).score
            let idx = idx
            let move = (score:score, idx:idx)
            moves.add(move)

        if player == this.aiPlayer:
          return max(moves)
          # var bestScore = -1000
          # var bestMove: Move
          # for m in moves:
          #   if m.score > bestScore:
          #     bestMove = m
          #     bestScore = m.score
          # return bestMove
        else:
          return min(moves)
          # var bestScore = 1000
          # var bestMove: Move
          # for m in moves:
          #   if m.score < bestScore:
          #     bestMove = m
          #     bestScore = m.score
          # return bestMove

```
Here we have a highly annotated `getBestMove` procedure to calculate recursively the best move for us

Now our startGame should look like this

```Nimrod
proc startGame*(this:Game): void=
    while true:
        ##old code

        ## AI check
        else:
            if this.currentPlayer == this.aiPlayer:
              let emptyspots = this.board.emptySpots()
              if len(emptyspots) <= this.difficulty:
                  echo("AI MOVE..")
                  let move = this.getbestmove(this.board, this.aiPlayer)
                  this.board.cells[move.idx] = this.aiPlayer
              else:
                  echo("RANDOM GUESS")
                  this.board.cells[emptyspots.rand()] = this.aiPlayer

        ## oldcode

```
Here we allow the game to use difficulty which means when does the AI starts calculating the moves and making the tree? from the beginning 9 cells left or when there're 4 cells left? you can set it the way you want it, and until u reach the starting difficulty situation AI will use random guesses (from the available `emptyspots`) instead of calculating

### CLI entry
```Nimrod
proc writeHelp() =
  echo """
TicTacToe 0.1.0 (MinMax version)
Allowed arguments:
  -h | --help         : show help
  -a | --ai           : AI player [X or O]
  -l | --difficulty   : destination to stow to
  """

proc cli*() =
  var
    aiplayer = ""
    difficulty = 9

  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
        case key
        of "help", "h":
            writeHelp()
            # quit()
        of "aiplayer", "a":
          echo "AIPLAYER: " & val
          aiplayer = val
        of "level", "l": difficulty = parseInt(val)
        else:
          discard
    else:
      discard

  let g = newGame(aiPlayer=aiplayer, difficulty=difficulty)
  g.startGame()


when isMainModule:
  cli()

```

Code is available on [https://github.com/xmonader/nim-tictactoe/blob/master/src/nim_tictactoe_cli.nim](https://github.com/xmonader/nim-tictactoe/blob/master/src/nim_tictactoe_cli.nim)
