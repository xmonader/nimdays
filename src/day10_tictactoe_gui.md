# Day 10: Tic tac toe with GUI!!
Hopefully, you're done with day 9 and enjoyed playing tic tac toe.

## Expectation
It's fun to play on the command line, but it'd be very cool to have some GUI with some buttons using [libui](https://github.com/nim-lang/ui) bindings in Nim

- make sure to install it using `nimble install ui`

## Implementation
In the previous day we reached some good abstraction separating the logic for the command line gui and the minmax algorithm and it's not tightly coupled 


### minimal ui application

```Nimrod
proc gui*() = 
  var mainwin = newWindow("tictactoe", 400, 500, true)
  show(mainwin)
  mainLoop()

when isMainModule:
  # cli()
  init()
  gui()
```

Here we create a window 400x500 with a title `tictactoe` and we show it and start its mainLoop `getting ready to receive and dispatch events`

### TicTacToe GUI

We can imagine the gui to be something like that

```
---------------------------------------------
|  ---------------------------------------  |
+  | INFO LABEL | button to restart       | +
|  ---------------------------------------| |
+  |--------------------------------------| +
|  |  btn     |    btn  |   btn           | |
+  |--------------------------------------| +
|  |  btn     |    btn  |   btn           | |
+  |--------------------------------------| +
|  |  btn     |    btn  |   btn           | |
+  |--------------------------------------| +
---------------------------------------------
```

- a window that contains  a vertical box
- the vertical box contains 4 rows 
- first row to show information about the current game and a button to reset the game
- and the other rows represent the 3x3 tictactoe grid that will reflect `game.list` :)
- and 9 buttons to be pressed to set X or O
- we will support human vs AI so when human presses a button it gets disabled and the AI presses the button that minimizes its loss and that button gets disabled too.

```Nimrod
proc gui*() = 
  var mainwin = newWindow("tictactoe", 400, 500, true)

  # game object to contain the state, the players, the difficulty,...
  var g = newGame(aiPlayer="O", difficulty=9)

  var currentMove = -1
  mainwin.margined = true
  mainwin.onClosing = (proc (): bool = return true)


  # set up the boxes 
  let box = newVerticalBox(true)
  let hbox0 = newHorizontalBox(true)
  let hbox1 = newHorizontalBox(true)
  let hbox2 = newHorizontalBox(true)
  let hbox3 = newHorizontalBox(true)
  # list of buttons 
  var buttons = newSeq[Button]()

  # information label
  var labelInfo = newLabel("Info: Player X turn")
  hbox0.add(labelInfo)

  # restart button
  hbox0.add(newButton("Restart", proc() = 
                            g =newGame(aiPlayer="O", difficulty=9)
                            for i, b in buttons.pairs:
                              b.text = $i
                              b.enable()))
```

Here we setup the layout we just described and create a button Restart that resets the game again and restore the buttons text and enables them all

```Nimrod
  # create the buttons
  for i in countup(0, 8):
    var handler : proc() 
    closureScope:
      let senderId = i
      handler = proc() =
        currentMove = senderId
        g.board.list[senderId] = g.currentPlayer
        g.change_player()
        labelInfo.text = "Current player: " & g.currentPlayer
        for i, v in g.board.list.pairs:
          buttons[i].text = v
        let (done, winner) = g.board.done()
        if done == true:
          echo g.board
          if winner == "tie":
              labelInfo.text = "Tie.."
          else:
            labelInfo.text = winner & " won."
        else:
          aiPlay()
        buttons[senderId].disable()

    buttons.add(newButton($i, handler))
 ```

 - Here we create the buttons please notice we are using `closureScope` feature to capture the button id to keep track of which button is clicked
 - after pressing set set the text of the button to `X`
 - we disable the button so we don't receive anymore events.
 - switch turns
 - update the information label whether about the next player or the game state
 - if the game is still going we ask the AI for a move


```Nimrod

  # code to run when the game asks the ai to play (after each move from the human..)
  proc aiPlay() = 
    if g.currentPlayer == g.aiPlayer:
      let emptySpots = g.board.emptySpots()
      if len(emptySpots) <= g.difficulty:
        let move = g.getBestMove(g.board, g.aiPlayer)
        g.board.list[move.idx] = g.aiPlayer
        buttons[move.idx].disable()
      else:
        let rndmove = emptyspots.rand()
        g.board.list[rndmove] = g.aiPlayer
    g.change_player()
    labelInfo.text = "Current player: " & g.currentPlayer

    for i, v in g.board.list.pairs:
      buttons[i].text = v
      
    let (done, winner) = g.board.done()

    if done == true:
      echo g.board
      if winner == "tie":
          labelInfo.text = "Tie.."
      else:
        labelInfo.text = winner & " won."

```

- using minmax algorithm from the previous day we calculate the best move
- change the button text to `O`
- disable the button
- update the information label

 ```Nimrod

  hbox1.add(buttons[0])
  hbox1.add(buttons[1])
  hbox1.add(buttons[2])

  hbox2.add(buttons[3])
  hbox2.add(buttons[4])
  hbox2.add(buttons[5])

  hbox3.add(buttons[6])
  hbox3.add(buttons[7])
  hbox3.add(buttons[8])
  
  box.add(hbox0, true)
  box.add(hbox1, true)
  box.add(hbox2, true)
  box.add(hbox3, true)
  mainwin.setChild(box)

```

- Here we add the buttons to their correct rows in the correct columns and set the main widget

```Nimrod
  show(mainwin)
  mainLoop()

when isMainModule:
  init()
  gui()
```

Code is available on [https://github.com/xmonader/nim-tictactoe/blob/master/src/nim_tictactoe_gui.nim](https://github.com/xmonader/nim-tictactoe/blob/master/src/nim_tictactoe_gui.nim)