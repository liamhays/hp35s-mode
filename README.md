# hp35s-mode
This is an Emacs major mode designed for editing programs for the HP
35s. It's pretty simple, but offers some useful features.

## Using it
Programs are stored with one command per line, just like the editor on
the 35s. Each file should have just one label. Unlike the editor, there are no line numbers, and a program just looks like this:

```
x2
yx
2
+
ENTER
Rdown
```

To work with character limitations, commands that use things like
alternate scripts and special symbols have alternate names, as
follows (all other operations are typed exactly how they're spelled on the calculator).

| Command operation                  | `hp35s-mode` name                     |
|------------------------------------|---------------------------------------|
| Roll down                          | Rdown                                 |
| Roll up                            | Rup                                   |
| y ^ x                              | yx                                    |
| x ^ 2                              | x2                                    |
| Integer division (INT÷)            | INTdiv                                |
|                                    |                                       |
| STO+, STO-, STO×, STO÷             | STOadd, STOsub, STOmul, STOdiv        |
| RCL+, RCL-, RCL×, RCL÷             | RCLadd, RCLsub, RCLmul, RCLdiv        |
| x≠y?, x≤y?, x≥y?, x<y?, x>y?, x=y? | x!=y?, x<=y?, x>=y?, x<y?, x>y?, x=y? |
| x≠0?, x≤0?, x≥0?, x<0?, x>0?, x=0? | x!=0?, x<=0?, x>=0?, x<0?, x>0?, x=0? |
|                                    |                                       |
| x exchange y                       | swap                                  |
| √x                                 | rootx                                 |
| x√y                                | xrooty                                |
| 1/x (invert)                       | 1/x                                   |
| 10 ^ x                             | 10x                                   |
| e ^ x                              | ex                                    |
| ←ENG                               | backENG                               |
| ENG→                               | ENGforw                               |
| +/- (negate)                       | chs                                   |
|                                    |                                       |
| ∫ FN d                             | integralFNd                           |
| Σ+                                 | E+                                    |
| Σ-                                 | E-                                    |
| Σx                                 | Ex                                    |
| Σy                                 | Ey                                    |
| Σx^2                               | Ex2                                   |
| Σy^2                               | Σy2                                   |
| Σxy                                | Exy                                   |
| x (overbar, stat function)         | xbar                                  |
| y (overbar)                        | ybar                                  |
| xw (overbar, weighted)             | xbarw                                 |
| σx                                 | sigmax                                |
| σy                                 | sigmay                                |
| Sx                                 | sx                                    |
| Sy                                 | sy                                    |
| x (with pointy hat)                | xhat                                  |
| y (with pointy hat)                | yhat                                  |
|                                    |                                       |
| radix on (DISPLAY->7)              | radixon                               |
| radix off (DISPLAY->8)             | radixoff                              |
| x𝑖y                                | xiy                                   |
| rθa                                | rthetaa                               |
|                                    |                                       |
| conversions (→F,→C, etc.)          | toF, toC, etc.                        |

### Features in the menu
- **Jump to line in GTO/XEQ instruction** This command reads the line
  referenced in the current line, which should look like "GTO X293" or
  similar. It then jumps to that line, relative to the label at the
  top of the program.
- **Return to last line jumped from** This will jump back to the last
  line where the previous command was called. There's only one level
  of history.
- **Print line number of current line relative to top** This will
  calculate the line number relative to the label the code is in.
- **Goto line in program relative to first label** This command asks
  you in the minibuffer for a line to go to, like "A031".
- **Estimate memory usage** This command is different: it iterates
  over the program, looking for commands and simple structures, and
  tries to estimate the amount of memory the program will use on the
  calculator. (Usage data from the Datafile V26 Special Issue about
  the HP 35s).
- **Import MoHPC Forum format program into buffer** Load a file with
  text in this format (what I call "MoHPC Forum" format, because it's
  used there):
```
M001 x^2
M002 y^x
```

  Loading the file will remove the labels automatically and replace
  the most common names for operations with the ones used by
  hp35s-mode. That means the above lines will become:
 
```
x2
yx
```

- **Export to MoHPC Forum format (as .txt)** This is basically the
  reverse of the above operation, converting the contents of the
  buffer to MoHPC Forum format---adding line numbers and replacing
  commands with alternate names.
