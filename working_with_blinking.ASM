; =============================================================================
; PROJECT:     Project 1 - Tic-Tac-Toe Game
; COURSE:      CC 421 Microprocessors Lab - Spring 2026
; HARDWARE:    MTS-86C 8086 Microcomputer Trainer Kit
; LECTURER:    Dr. Nayera Sadek
; Mohamed Yasser Samak    24011107
; Elsayed Ashraf Bakry    23010293
; Adham Khattab           24010991
; =============================================================================

; --- Hardware Address Definitions ---
CNT3    EQU  3FD6H      ; 8255-3 Control Word Register address
BPORT3  EQU  3FD2H      ; 8255-3 Port B address (connected to 8 LEDs)

; --- 8279 Keypad Controller Addresses (from MTS-86C I/O Map) ---
KBD_CMD EQU  0FFEAH     ; 8279 Status / Command Word Register
KBD_DAT EQU  0FFE8H     ; 8279 Data Register (key FIFO read port)

; --- LCD Controller Addresses (from MTS-86C I/O Map, Figure 1-3) ---
LCD_DAT EQU  0FFC5H     ; LCD Data Write port
LCD_STA EQU  0FFC3H     ; LCD Instruction (Status) Read port
LCD_CMD EQU  0FFC1H     ; LCD Instruction (Command) Write port

; --- Game Constants ---
BLINK_COUNT EQU 08H     ; (Legacy constant - superseded by BLINK_REPS in HARDWARE_OUTPUT)-->LEDS

; =============================================================================
CODE    SEGMENT
        ASSUME CS:CODE, DS:CODE

        ORG 0           ; Kit monitor loads and executes from offset 0000H

START:
        ; --- Setup Stack Pointer (as per all Lab Manual examples) ---
        MOV  SP, 4000H          ; Initialize stack pointer to safe area

        ; --- Initialize the Data Segment Register ---
        ; MOV DS, CS is illegal on 8086 -> must route through AX.
        MOV  AX, CS             ; Load Code Segment address into AX
        MOV  DS, AX             ; DS = CS -> all data offsets resolve correctly

        ; ================================================================
        ; HARDWARE INIT: Configure 8255 PPI Control Register
        ; Control Word 90H = 1001 0000B:
        ;   D7=1  -> I/O Mode active (mandatory)
        ;   D6D5=00 -> Group A: Mode 0 (Basic I/O)
        ;   D4=1  -> Port A = INPUT
        ;   D3=0  -> Port C upper = OUTPUT
        ;   D2=0  -> Group B: Mode 0 (Basic I/O)
        ;   D1=0  -> Port B = OUTPUT  (drives our 8 LEDs)
        ;   D0=0  -> Port C lower = OUTPUT
        ; ================================================================
        MOV  AL, 90H            ; Load the 8255 control word (90H)
        MOV  DX, CNT3           ; Point DX to Control Register (3FD6H)
        OUT  DX, AL             ; HARDWARE WRITE: Configure 8255 PPI

        ; --- Clear LEDs at startup ---
        MOV  AL, 00H            ; All LEDs OFF
        MOV  DX, BPORT3         ; Point DX to Port B (3FD2H)
        OUT  DX, AL             ; HARDWARE WRITE: All LEDs off initially

        ; --- Display Welcome Banner ---
        LEA  DX, MSG_WELCOME    ; Load address of welcome string
        MOV  AH, 09H            ; DOS function: Print String
        INT  21H                ; Output to Tera Term via RS-232

; =============================================================================
MAIN_LOOP:

        ; --- Step 1: Draw the current board ---
        CALL DRAW_BOARD

        ; --- Step 2: Print the player prompt ---
        LEA  DX, MSG_PROMPT     ; Print "Player "
        MOV  AH, 09H
        INT  21H

        ; Print the current player symbol dynamically from the PLAYER variable.
        ; INT 21H AH=02H outputs a single character from DL to the terminal.
        MOV  DL, PLAYER         ; Load current player's symbol ('X' or 'O')
        MOV  AH, 02H            ; DOS function: Print Character
        INT  21H

        LEA  DX, MSG_TURN       ; Print ", enter your move (1-9): "
        MOV  AH, 09H
        INT  21H

; =============================================================================
; GET_INPUT  (KIT KEYPAD VERSION)

GET_INPUT:
        ; --- Poll 8279 Status Register until a key is available ---
        MOV  DX, KBD_CMD        ; Point DX to 8279 Status Register (FFEAH)
KBD_POLL:
        ; ASK STATUS REGISTER IF SOMEONE CLICKED ON THE KEYBAD OR NOT???
        IN   AL, DX             ; HARDWARE READ: fetch 8279 Status byte
        AND  AL, 01H            ; Isolate bit 0 (FIFO Data Available flag)
        JZ   KBD_POLL           ; Bit 0 = 0 -> no key yet, keep polling

        ;read the data coming fron the button
        MOV  DX, KBD_DAT        ; Point DX to 8279 Data Register (FFE8H)
        IN   AL, DX             ; HARDWARE READ: pop scan code from FIFO -> AL
                                ; AL = 00H for key "1", 01H for "2", ..., 08H for "9"

        ; --- Validate: only scan codes 00H..08H are cells 1..9 ---
        ; JA fires when AL > 08H (unsigned), rejecting all other keypad keys.
        CMP  AL, 09H            ; Is scan code > 08H? (beyond key "9")
        JA   INVALID_INPUT      ; Yes -> not a valid cell key, re-prompt, JUMP IF BIGGER THAN(Hahaha)

        ; --- Convert scan code to ASCII digit ---
        ; Raw scan code 00H..08H + 31H -> ASCII '1'..'9' (31H..39H)
        ADD  AL, '0'            ; AL is now the ASCII character '1'-'9'

        ; --- Echo the chosen digit to Tera Term so the player can see it ---
        MOV  DL, AL             ; Copy ASCII digit to DL for output
        PUSH AX                 ; Preserve AL across the INT 21H call
        MOV  AH, 02H            ; DOS function: Print Character
        INT  21H                ; Echo the digit to Tera Term via RS-232
        POP  AX                 ; Restore AL (the validated ASCII digit)

        ; --- AL is now guaranteed in '1'..'9' ---
        JMP  IN_RANGE           ; Valid key received -> proceed

INVALID_INPUT:
        ; The character was not a valid digit '1'-'9'.
        ; Reprint the prompt and wait for a correct input.
        LEA  DX, MSG_PROMPT
        MOV  AH, 09H
        INT  21H
        MOV  DL, PLAYER
        MOV  AH, 02H
        INT  21H
        LEA  DX, MSG_TURN
        MOV  AH, 09H
        INT  21H
        JMP  GET_INPUT          ; Read again from the top of the fixed loop

IN_RANGE:
        ; --- Step 4: Convert ASCII digit to 0-based array index ---
        MOV  BL, AL             ; Copy the validated digit into BL
        SUB  BL, '1'            ; BL = 0-based index into GRID array

        MOV  BH, 0              ; BH = 0, so BX = 0..8 (no stray high byte)

        ; --- Step 5: Check if the chosen cell is already occupied ---
        ; A free cell holds its digit ('1'-'9'). A taken cell holds 'X' or 'O'.
        CMP  GRID[BX], 'X'     ; Is this cell already claimed by Player 1?
        JZ   CELL_TAKEN         ; Yes -> reject this move
        CMP  GRID[BX], 'O'     ; Is this cell already claimed by Player 2?
        JZ   CELL_TAKEN         ; Yes -> reject this move
        JMP  PLACE_MARK         ; Cell is free -> go place the symbol

CELL_TAKEN:
        ; Cell already occupied. Print error and restart the full turn.
        LEA  DX, MSG_TAKEN
        MOV  AH, 09H
        INT  21H
        JMP  MAIN_LOOP          ; Redraw board and re-prompt the same player

PLACE_MARK:
        ; --- Step 6: Write the current player's symbol into the GRID array ---
        MOV  AL, PLAYER         ; Load 'X' or 'O'
        MOV  GRID[BX], AL       ; Write symbol to the chosen cell

        ; --- Increment the move counter ---
        INC  MOVES              ; Track total moves for draw detection

        ; --- Step 7: Check for a winning condition ---
        CALL CHECK_WIN          ; Returns AL=1 if win detected, AL=0 otherwise
        CMP  AL, 1
        JZ   GAME_WIN           ; Current player has won

        ; --- Step 8: Check for a draw ---
        CMP  MOVES, 9           ; All 9 cells filled with no winner?
        JZ   GAME_DRAW          ; Yes -> draw

        ; --- Step 9: Switch to the other player ---
        CMP  PLAYER, 'X'        ; Is it currently Player X's turn?
        JNZ  SET_TO_X           ; No -> it must be O, switch to X
        MOV  PLAYER, 'O'        ; Was X -> now O's turn
        JMP  MAIN_LOOP

SET_TO_X:
        MOV  PLAYER, 'X'        ; Was O -> now X's turn
        JMP  MAIN_LOOP

; =============================================================================
; GAME RESULT HANDLERS

GAME_WIN:
        CALL DRAW_BOARD         ; Show the final winning board

        LEA  DX, MSG_WIN        ; Print "Player "
        MOV  AH, 09H
        INT  21H
        MOV  DL, PLAYER         ; Print the winning player's symbol
        MOV  AH, 02H
        INT  21H
        LEA  DX, MSG_WIN2       ; Print " WINS! Congratulations! ..."
        MOV  AH, 09H
        INT  21H

        ; --- LCD Win Message ---
        CALL LCD_WIN_MSG            ; Display "Px WINS!" on kit LCD

        ; --- LED Celebration (infinite - CPU stays here until kit reset) ---
        CALL HARDWARE_OUTPUT        ; Rotate LEDs forever - never returns

        JMP  GAME_END               ; Unreachable: kept so assembler resolves label

GAME_DRAW:
        CALL DRAW_BOARD         ; Show the final drawn board

        LEA  DX, MSG_DRAW       ; Print the draw message
        MOV  AH, 09H
        INT  21H

        ; --- LCD Draw Message ---
        CALL LCD_DRAW_MSG           ; Display "** DRAW! **" on kit LCD

GAME_END:
        LEA  DX, MSG_AGAIN      ; Print "Press any key to exit..."
        MOV  AH, 09H
        INT  21H
        MOV  AH, 01H
        INT  21H                ; Wait for final keypress

        ; --- Turn off all LEDs cleanly before exiting ---
        MOV  AL, 00H
        MOV  DX, BPORT3
        OUT  DX, AL             ; HARDWARE WRITE: All LEDs off on exit

        ; --- Terminate and return to MTS-86C monitor ---
        MOV  AH, 4CH
        INT  21H

; =============================================================================
; SUBROUTINE: DRAW_BOARD

DRAW_BOARD PROC NEAR

        ; --- Top border + row 1 frame + cell 1 placeholder ---
        LEA  DX, MSG_TOP
        MOV  AH, 09H
        INT  21H

        MOV  DL, GRID[0]        ; Cell 1
        MOV  AH, 02H
        INT  21H

        LEA  DX, MSG_SEP1
        MOV  AH, 09H
        INT  21H

        MOV  DL, GRID[1]        ; Cell 2
        MOV  AH, 02H
        INT  21H

        LEA  DX, MSG_SEP2
        MOV  AH, 09H
        INT  21H

        MOV  DL, GRID[2]        ; Cell 3
        MOV  AH, 02H
        INT  21H

        ; --- Row 1 close + middle border + row 2 frame ---
        LEA  DX, MSG_ROW1END
        MOV  AH, 09H
        INT  21H

        MOV  DL, GRID[3]        ; Cell 4
        MOV  AH, 02H
        INT  21H

        LEA  DX, MSG_SEP3
        MOV  AH, 09H
        INT  21H

        MOV  DL, GRID[4]        ; Cell 5
        MOV  AH, 02H
        INT  21H

        LEA  DX, MSG_SEP4
        MOV  AH, 09H
        INT  21H

        MOV  DL, GRID[5]        ; Cell 6
        MOV  AH, 02H
        INT  21H

        ; --- Row 2 close + middle border + row 3 frame ---
        LEA  DX, MSG_ROW2END
        MOV  AH, 09H
        INT  21H

        MOV  DL, GRID[6]        ; Cell 7
        MOV  AH, 02H
        INT  21H

        LEA  DX, MSG_SEP5
        MOV  AH, 09H
        INT  21H

        MOV  DL, GRID[7]        ; Cell 8
        MOV  AH, 02H
        INT  21H

        LEA  DX, MSG_SEP6
        MOV  AH, 09H
        INT  21H

        MOV  DL, GRID[8]        ; Cell 9
        MOV  AH, 02H
        INT  21H

        ; --- Row 3 close + bottom border ---
        LEA  DX, MSG_ROW3END
        MOV  AH, 09H
        INT  21H

        RET
DRAW_BOARD ENDP

; =============================================================================
; SUBROUTINE: CHECK_WIN
; Purpose : Checks all 8 winning lines for the current player's symbol.
; Returns : AL = 1 if win found, AL = 0 if not.
;
; All 8 winning combinations on a 3x3 grid (0-based indices):
;   Rows      : [0,1,2]  [3,4,5]  [6,7,8]
;   Columns   : [0,3,6]  [1,4,7]  [2,5,8]
;   Diagonals : [0,4,8]  [2,4,6]

CHECK_WIN PROC NEAR

        MOV  CH, PLAYER         ; CH = symbol to look for ('X' or 'O')
        MOV  AL, 0              ; Default return: no win

        ; --- Row 1: cells 0, 1, 2 ---
        CMP  GRID[0], CH
        JNZ  CHK_ROW2
        CMP  GRID[1], CH
        JNZ  CHK_ROW2
        CMP  GRID[2], CH
        JNZ  CHK_ROW2
        JMP  WIN_FOUND

CHK_ROW2:
        ; --- Row 2: cells 3, 4, 5 ---
        CMP  GRID[3], CH
        JNZ  CHK_ROW3
        CMP  GRID[4], CH
        JNZ  CHK_ROW3
        CMP  GRID[5], CH
        JNZ  CHK_ROW3
        JMP  WIN_FOUND

CHK_ROW3:
        ; --- Row 3: cells 6, 7, 8 ---
        CMP  GRID[6], CH
        JNZ  CHK_COL1
        CMP  GRID[7], CH
        JNZ  CHK_COL1
        CMP  GRID[8], CH
        JNZ  CHK_COL1
        JMP  WIN_FOUND

CHK_COL1:
        ; --- Column 1: cells 0, 3, 6 (step = 3) ---
        CMP  GRID[0], CH
        JNZ  CHK_COL2
        CMP  GRID[3], CH
        JNZ  CHK_COL2
        CMP  GRID[6], CH
        JNZ  CHK_COL2
        JMP  WIN_FOUND

CHK_COL2:
        ; --- Column 2: cells 1, 4, 7 ---
        CMP  GRID[1], CH
        JNZ  CHK_COL3
        CMP  GRID[4], CH
        JNZ  CHK_COL3
        CMP  GRID[7], CH
        JNZ  CHK_COL3
        JMP  WIN_FOUND

CHK_COL3:
        ; --- Column 3: cells 2, 5, 8 ---
        CMP  GRID[2], CH
        JNZ  CHK_DIAG1
        CMP  GRID[5], CH
        JNZ  CHK_DIAG1
        CMP  GRID[8], CH
        JNZ  CHK_DIAG1
        JMP  WIN_FOUND

CHK_DIAG1:
        ; --- Main diagonal: cells 0, 4, 8 (top-left -> bottom-right) ---
        CMP  GRID[0], CH
        JNZ  CHK_DIAG2
        CMP  GRID[4], CH
        JNZ  CHK_DIAG2
        CMP  GRID[8], CH
        JNZ  CHK_DIAG2
        JMP  WIN_FOUND

CHK_DIAG2:
        ; --- Anti-diagonal: cells 2, 4, 6 (top-right -> bottom-left) ---
        CMP  GRID[2], CH
        JNZ  NO_WIN
        CMP  GRID[4], CH
        JNZ  NO_WIN
        CMP  GRID[6], CH
        JNZ  NO_WIN
        JMP  WIN_FOUND

WIN_FOUND:
        MOV  AL, 1              ; Return 1 = win detected
        RET

NO_WIN:
        MOV  AL, 0              ; Return 0 = no win
        RET

CHECK_WIN ENDP

; =============================================================================
; SUBROUTINE: LCD_WAIT
; Purpose : Busy-wait until the LCD controller is ready.
;           Polls LCD Status port (FFC3H) bit 7 (BF = Busy Flag).
;           BF=1 means LCD is busy; BF=0 means ready to accept a command/data.
; Modifies: AL, DX
; =============================================================================
LCD_WAIT PROC NEAR
LCD_BUSY:
        MOV  DX, LCD_STA        ; Point DX to LCD Status Read port (FFC3H)
        IN   AL, DX             ; Read LCD status byte
        TEST AL, 80H            ; Test bit 7 (Busy Flag)
        JNZ  LCD_BUSY           ; BF=1 -> LCD busy, keep polling
        RET                     ; BF=0 -> LCD ready
LCD_WAIT ENDP

; =============================================================================
; SUBROUTINE: LCD_CMD_WRITE
; Purpose : Send one command byte (in AL) to the LCD controller.
; Input   : AL = command byte
; Modifies: DX
; =============================================================================
LCD_CMD_WRITE PROC NEAR
        PUSH AX                 ; Preserve AL across the busy-wait call
        CALL LCD_WAIT           ; Wait until LCD is not busy
        POP  AX                 ; Restore the command byte
        MOV  DX, LCD_CMD        ; Point DX to LCD Command Write port (FFC1H)
        OUT  DX, AL             ; HARDWARE WRITE: Send command to LCD
        RET
LCD_CMD_WRITE ENDP

; =============================================================================
; SUBROUTINE: LCD_DAT_WRITE
; Purpose : Send one data byte (character) in AL to the LCD display RAM.
; Input   : AL = ASCII character to display
; Modifies: DX
; =============================================================================
LCD_DAT_WRITE PROC NEAR
        PUSH AX                 ; Preserve AL across the busy-wait call
        CALL LCD_WAIT           ; Wait until LCD is not busy
        POP  AX                 ; Restore the data byte
        MOV  DX, LCD_DAT        ; Point DX to LCD Data Write port (FFC5H)
        OUT  DX, AL             ; HARDWARE WRITE: Send character to LCD
        RET
LCD_DAT_WRITE ENDP

; =============================================================================
; SUBROUTINE: LCD_WIN_MSG
; Purpose : Initialises the LCD and writes a two-line win message:
;             Line 1 (row 0): "  PLAYER X WINS "   (X or O from PLAYER var)
;             Line 2 (row 1): " CONGRATULATIONS"
; Called from : GAME_WIN (after Tera Term output, before GAME_END)
; Modifies: AX, BX, DX
; =============================================================================
LCD_WIN_MSG PROC NEAR

        ; --- Initialise LCD: Function Set -> 8-bit, 2 lines, 5x7 font ---
        MOV  AL, 38H            ; CMD 38H: 8-bit bus, 2-line, 5x7
        CALL LCD_CMD_WRITE

        ; --- Display ON, cursor OFF, blink OFF ---
        MOV  AL, 0CH            ; CMD 0CH: Display ON, cursor off
        CALL LCD_CMD_WRITE

        ; --- Clear Display ---
        MOV  AL, 01H            ; CMD 01H: Clear display, return home
        CALL LCD_CMD_WRITE

        ; --- Entry Mode: increment address, no display shift ---
        MOV  AL, 06H            ; CMD 06H: Increment cursor, no shift
        CALL LCD_CMD_WRITE

        ; --- Set DDRAM address to line 1 start (00H) ---
        MOV  AL, 80H            ; CMD 80H: DDRAM address = 00H (line 1)
        CALL LCD_CMD_WRITE

        ; --- Write Line 1: "  PLAYER " ---
        LEA  BX, LCD_STR_WIN1   ; BX -> first char of "  PLAYER "
LCD_WIN_L1:
        MOV  AL, [BX]           ; Load next character
        CMP  AL, 0              ; NULL terminator?
        JZ   LCD_WIN_INSERT_SYM ; Yes -> insert player symbol next
        CALL LCD_DAT_WRITE      ; No  -> write char to LCD
        INC  BX                 ; Advance pointer
        JMP  LCD_WIN_L1

LCD_WIN_INSERT_SYM:
        ; --- Insert the winning player symbol ('X' or 'O') ---
        MOV  AL, PLAYER         ; Load 'X' or 'O'
        CALL LCD_DAT_WRITE      ; Write symbol to LCD

        ; --- Write remainder of Line 1: " WINS!" ---
        LEA  BX, LCD_STR_WIN1B  ; BX -> " WINS!  "
LCD_WIN_L1B:
        MOV  AL, [BX]
        CMP  AL, 0
        JZ   LCD_WIN_LINE2
        CALL LCD_DAT_WRITE
        INC  BX
        JMP  LCD_WIN_L1B

LCD_WIN_LINE2:
        ; --- Set DDRAM address to line 2 start (40H) ---
        MOV  AL, 0C0H           ; CMD C0H: DDRAM address = 40H (line 2)
        CALL LCD_CMD_WRITE

        ; --- Write Line 2: " CONGRATULATIONS" ---
        LEA  BX, LCD_STR_WIN2
LCD_WIN_L2:
        MOV  AL, [BX]
        CMP  AL, 0
        JZ   LCD_WIN_DONE
        CALL LCD_DAT_WRITE
        INC  BX
        JMP  LCD_WIN_L2

LCD_WIN_DONE:
        RET
LCD_WIN_MSG ENDP

; =============================================================================
; SUBROUTINE: LCD_DRAW_MSG
; Purpose : Writes a two-line draw message on the LCD:
;             Line 1: "** DRAW GAME!! **"
;             Line 2: " WELL PLAYED!   "
; Called from : GAME_DRAW (after Tera Term output, before GAME_END)
; Modifies: AX, BX, DX
; =============================================================================
LCD_DRAW_MSG PROC NEAR

        ; --- Initialise LCD (same sequence as LCD_WIN_MSG) ---
        MOV  AL, 38H
        CALL LCD_CMD_WRITE
        MOV  AL, 0CH
        CALL LCD_CMD_WRITE
        MOV  AL, 01H
        CALL LCD_CMD_WRITE
        MOV  AL, 06H
        CALL LCD_CMD_WRITE

        ; --- Set DDRAM address to line 1 start ---
        MOV  AL, 80H
        CALL LCD_CMD_WRITE

        ; --- Write Line 1 ---
        LEA  BX, LCD_STR_DRAW1
LCD_DRAW_L1:
        MOV  AL, [BX]
        CMP  AL, 0
        JZ   LCD_DRAW_LINE2
        CALL LCD_DAT_WRITE
        INC  BX
        JMP  LCD_DRAW_L1

LCD_DRAW_LINE2:
        ; --- Set DDRAM address to line 2 start ---
        MOV  AL, 0C0H
        CALL LCD_CMD_WRITE

        ; --- Write Line 2 ---
        LEA  BX, LCD_STR_DRAW2
LCD_DRAW_L2:
        MOV  AL, [BX]
        CMP  AL, 0
        JZ   LCD_DRAW_DONE
        CALL LCD_DAT_WRITE
        INC  BX
        JMP  LCD_DRAW_L2

LCD_DRAW_DONE:
        RET
LCD_DRAW_MSG ENDP

; =============================================================================
; SUBROUTINE: HARDWARE_OUTPUT  (LED WIN CELEBRATION - INFINITE ROTATE LEFT)

HARDWARE_OUTPUT PROC NEAR

        MOV  DX, BPORT3         ; Point DX to 8255-3 Port B (3FD2H) - 8 LEDs
        MOV  AL, 01H            ; Start: only LED L1 lit (bit 0 = 1)

LED_SHIFT_LOOP:
        OUT  DX, AL             ; HARDWARE WRITE: output current LED pattern
        MOV  CX, 0A00H         ; Delay count (same as lab manual Ex.2)
        LOOP $                  ; Burn cycles for visible delay

        ROL  AL, 1              ; Rotate AL left by 1 bit:
                                ;   01H->02H->04H->...->80H->01H (wraps via carry)
        JMP  LED_SHIFT_LOOP     ; Repeat forever - game is over, no exit needed

HARDWARE_OUTPUT ENDP

; =============================================================================
; DATA AREA
; Placed AFTER all ENDP directives (end of executable code).


        ; --- The Game Board ---
        ; 9 bytes, initialized '1'-'9'. Free cells keep their digit.
        ; Taken cells are overwritten with 'X' or 'O' by PLACE_MARK.
GRID    DB  '1','2','3','4','5','6','7','8','9'

        ; --- Current Player Symbol ('X' starts first) ---
PLAYER  DB  'X'

        ; --- Move Counter (0-9, used to detect a draw at 9) ---
MOVES   DB  0

        ; --- Welcome Banner ---
        ; CR(0DH) + LF(0AH) before each line for clean Tera Term display.
        ; '$' terminates every string for INT 21H AH=09H.
MSG_WELCOME DB  0DH, 0AH
            DB  '============================================', 0DH, 0AH
            DB  '   TIC-TAC-TOE - MTS-86C 8086 Trainer     ', 0DH, 0AH
            DB  '   CC421 Microprocessors - Spring 2026     ', 0DH, 0AH
            DB  '============================================', 0DH, 0AH
            DB  '  Player 1 = X  |  Player 2 = O           ', 0DH, 0AH
            DB  '  Press kit keypad key 1-9 for your move.  ', 0DH, 0AH
            DB  '============================================', 0DH, 0AH, '$'

        ; --- Board Frame Strings ---
        ; DRAW_BOARD interleaves these strings with live GRID[] characters.
        ; Each string ends at '$' immediately before the next cell is inserted.
MSG_TOP     DB  0DH, 0AH
            DB  '  +-------+-------+-------+', 0DH, 0AH
            DB  '  |       |       |       |', 0DH, 0AH
            DB  '  |  $'
MSG_SEP1    DB  '  |  $'
MSG_SEP2    DB  '  |  $'
MSG_ROW1END DB  '  |', 0DH, 0AH
            DB  '  |       |       |       |', 0DH, 0AH
            DB  '  +-------+-------+-------+', 0DH, 0AH
            DB  '  |       |       |       |', 0DH, 0AH
            DB  '  |  $'
MSG_SEP3    DB  '  |  $'
MSG_SEP4    DB  '  |  $'
MSG_ROW2END DB  '  |', 0DH, 0AH
            DB  '  |       |       |       |', 0DH, 0AH
            DB  '  +-------+-------+-------+', 0DH, 0AH
            DB  '  |       |       |       |', 0DH, 0AH
            DB  '  |  $'
MSG_SEP5    DB  '  |  $'
MSG_SEP6    DB  '  |  $'
MSG_ROW3END DB  '  |', 0DH, 0AH
            DB  '  |       |       |       |', 0DH, 0AH
            DB  '  +-------+-------+-------+', 0DH, 0AH, '$'

        ; --- Player Prompt (player symbol printed separately via AH=02H) ---
MSG_PROMPT  DB  0DH, 0AH, 'Player $'
MSG_TURN    DB  ', press keypad key (1-9): $'

        ; --- Cell Already Taken Error ---
MSG_TAKEN   DB  0DH, 0AH, '  *** Cell already taken! Try again. ***'
            DB  0DH, 0AH, '$'

        ; --- Win Message (winning symbol printed separately via AH=02H) ---
MSG_WIN     DB  0DH, 0AH
            DB  '============================================', 0DH, 0AH
            DB  '  >>>  Player $'
MSG_WIN2    DB  ' WINS! Congratulations!  <<<', 0DH, 0AH
            DB  '============================================', 0DH, 0AH, '$'

        ; --- Draw Message ---
MSG_DRAW    DB  0DH, 0AH
            DB  '============================================', 0DH, 0AH
            DB  '  >>>  DRAW GAME! Well played, both!  <<<  ', 0DH, 0AH
            DB  '============================================', 0DH, 0AH, '$'

        ; --- Exit Prompt ---
MSG_AGAIN   DB  0DH, 0AH, '  Press any key to exit...', 0DH, 0AH, '$'


LCD_STR_WIN1  DB  '  PLAYER ', 0       ; 9 chars; player symbol inserted after
LCD_STR_WIN1B DB  ' WINS!  ', 0        ; 8 chars; completes line 1 (9+1+6=16)
LCD_STR_WIN2  DB  'CONGRATULATIONS!', 0

LCD_STR_DRAW1 DB  '** DRAW GAME!! **', 0
LCD_STR_DRAW2 DB  ' WELL PLAYED!   ', 0

CODE    ENDS
        END  START

