; -------------------------------------------------------------------
; 80386
; 32-bit x86 assembly language
; TASM
;
; author:	David Blinder, Stijn Bettens
; date:		23/10/2018
; program:	Video mode 13h
; -------------------------------------------------------------------

IDEAL
P386
MODEL FLAT, C
ASSUME cs:_TEXT,ds:FLAT,es:FLAT,fs:FLAT,gs:FLAT

; compile-time constants (with macros)
VMEMADR EQU 0A0000h	; video memory address
SCRWIDTH EQU 320	; screen witdth
SCRHEIGHT EQU 200	; screen height
ROWS EQU 5		; number of rows
COLUMNS EQU 20		; number of columns

; -------------------------------------------------------------------
CODESEG

; Set the video mode
PROC setVideoMode
	ARG 	@@VM:byte
	USES 	eax

	movzx ax,[@@VM]
	int 10h

	ret
ENDP setVideoMode
PROC fillBackground
	ARG @@color:BYTE
    USES edi, ecx
        	mov edi, VMEMADR    ; Point EDI to video memory
        	mov al, [@@color]     ; Load the color into AL
        	mov ecx, SCRWIDTH * SCRHEIGHT ; Number of pixels
        	REP stosb           ; Fill video memory with the color
        	ret
ENDP fillBackground

; Check if a specific keystroke is pressed.
; If the specified key is pressed, exit the program.
; Otherwise, return.
PROC checkForSpecificKeystroke
    ARG     @@key:byte
    USES    eax

    ; Check if a key is pressed
    mov     ah, 01h
    int     16h
    jz      @@noKeyPressed  ; If no key is pressed, jump to @@noKeyPressed

    ; Read the key code
    mov     ah, 00h
    int     16h

    ; Compare the key code with the specified key
    cmp     al, [@@key]
    jne     @@noKeyPressed  ; If the key does not match, jump to @@noKeyPressed

    ; If the key matches, exit the program
    call    terminateProcess

@@noKeyPressed:
    ret
ENDP checkForSpecificKeystroke

; Wait for a specific keystroke.
PROC waitForSpecificKeystroke
	ARG 	@@key:byte
	USES 	eax

	@@waitForKeystroke:
		mov	ah,00h
		int	16h
		cmp	al,[@@key]
	jne	@@waitForKeystroke

	ret
ENDP waitForSpecificKeystroke

; Terminate the program.
PROC terminateProcess
	USES eax
	call setVideoMode, 03h
	mov	ax,04C00h
	int 21h
	ret
ENDP terminateProcess

; print decimal number
PROC printDecimal
    ARG @@number:DWORD
    USES eax, ebx, ecx, edx

            mov	eax, [@@number]
            mov ebx, 10
            xor ecx, ecx

        getNextDigit:
            inc ecx
            xor edx, edx
            div ebx
            push dx ; store remainder on stack
            test eax, eax ; if zero, last digit
            jnz	getNextDigit

            mov ah, 02h
        printDigits:
            pop dx
            add dl, '0'
            int 21h
            loop printDigits

            mov	dl, 0Dh		; Carriage return.
            int	21h
            mov	dl, 0Ah		; New line.
            int 21h

            ret
ENDP printDecimal

; print grid to screen in text mode
PROC printGrid
    ARG @@bias:BYTE, @@grid:DWORD
    USES eax, ebx, ecx, edx

    ; iterate over rows
    ; for each row iterate over columns
    ; print the value of the grid at the current row and column

    mov esi, [@@grid]               ; Set ESI to point to the grid array
    mov cx, ROWS                    ; Set CX to the number of rows
    mov dx, COLUMNS                 ; Set DX to the number of columns

    outer_loop_draw:
        push cx                         ; Save outer loop counter
        mov cx, dx                      ; Set inner loop counter

    inner_loop_draw:
        lodsb                           ; Load byte at [ESI] into AL and increment ESI
        mov bl, [@@bias]
        add esi, ebx
        cmp al, -1                       ; Compare AL with zero
        je print_zero                   ; If zero, jump to print_zero
        add al, '0'                     ; Otherwise, set AL to the ASCII value of the digit
        jmp print_char                  ; Jump to print_char

    print_zero:
        mov al, ':'                     ; Set AL to '0'

    print_char:
        mov ah, 0Eh                     ; BIOS teletype function
        int 10h                         ; Call BIOS interrupt to print character
        loop inner_loop_draw            ; Repeat for each column

        ; Print newline
        mov al, 0Dh                     ; Carriage return
        int 10h                         ; Call BIOS interrupt to print character
        mov al, 0Ah                     ; Line feed
        int 10h                         ; Call BIOS interrupt to print character

        pop cx                          ; Restore outer loop counter
        loop outer_loop_draw            ; Repeat for each row

        ; Print newline
        mov al, 0Dh                     ; Carriage return
        int 10h                         ; Call BIOS interrupt to print character
        mov al, 0Ah                     ; Line feed
        int 10h                         ; Call BIOS interrupt to print character

        ret
ENDP printGrid

; change content of a cell in the grid
PROC updateCell
    ARG @@x:BYTE, @@y:BYTE, @@value:BYTE
    USES eax, ebx, edi

    ; Calculate the offset of the cell in the grid
    mov edi, offset grid
    movzx eax, [@@y]
    imul eax, COLUMNS
    imul eax, 8
    movzx ebx, [@@x]
    imul ebx, 8
    add eax, ebx

    ; Set the value of the cell
    add edi, eax
    mov al, [@@value]
    stosb

    ret

ENDP updateCell

; function to move an entity from one position to another
PROC moveCell
    ARG @@x1:BYTE, @@y1:BYTE, @@x2:BYTE, @@y2:BYTE
    USES eax, ebx, ecx, edx, esi

        ; use the updateCell function to move the entity
        mov esi, offset grid
        movzx eax, [@@y1]
        imul eax, COLUMNS
        add al, [@@x1]
        add esi, eax
        lodsb
        push eax

        mov al, [@@x2]
        mov bl, [@@y2]
        pop ecx
        call updateCell, eax, ebx, ecx

        mov al, [@@x1]
        mov bl, [@@y1]
        call updateCell, eax, ebx, -1

        ret
ENDP moveCell

; -------------------------------------------------------------------

; dynamic grid functions

; function to change content of a cell in the dynamic grid
PROC updateDynamicCell
    ARG @@x:BYTE, @@y:BYTE, @@value:BYTE
    USES eax, ebx, ecx, edx, edi

    ; Calculate the offset of the cell in the grid
    mov edi, offset dynamic_grid
    movzx eax, [@@y]
    imul eax, COLUMNS
    add al, [@@x]
    add edi, eax

    ; Set the value of the cell
    mov al, [@@value]
    stosb

    ret

ENDP updateDynamicCell

; function to initialize a new entity in the dynamic entities array
; returns the index of the entity in the dynamic entities array on the stack if successful
; returns -1 on the stack if the dynamic entities array is full -- TODO
PROC addDynamicEntitytoArray
    ARG @@type:BYTE ; lets start with just adding a type
    USES eax, ebx, ecx, edx, edi

        ; Load the value of free_index into eax
        mov al, [free_index]
        movzx eax, al  ; Zero-extend al to eax to ensure correct offset calculation

        ; Calculate the address of the first free index in the dynamic_entities_array
        mov edi, offset dynamic_entities_array
        add edi, eax

        ; Store the entity type at the calculated position
        mov al, [@@type]
        stosb

        ; push the free_index used
        mov al, [free_index]
        push eax

        call printDecimal, eax

        ; Increment the free_index
        mov al, [free_index]
        inc al
        mov [free_index], al
        
    ret
ENDP addDynamicEntitytoArray

; function to print state of an entity in the dynamic entities array
PROC printDynamicEntityState
    ARG @@index: BYTE
    USES eax, ebx, ecx, edx, edi

    ; Get the entity at the specified index
    mov al, [@@index]
    movzx eax, al  ; Zero-extend al to eax to ensure correct offset calculation
    mov edi, offset dynamic_entities_array
    add edi, eax
    lodsb

    ; Print the entity state - let's start with just the type
    add al, '0'
    mov ah, 0Eh
    int 10h

    ret
ENDP printDynamicEntityState

; function that initializes an entity
PROC initializeDynamicEntity
    ARG @@x:BYTE, @@y:BYTE, @@type:BYTE 
    USES eax, ebx, ecx, edx, edi

    ; initialize the entity in the dynamic_entities_array
    ; lets start with just adding a type
    ; put the index of the entity in dynamic_entities_array into the dynamic_grid

    ; Pass the entity type to addDynamicEntitytoArray
    xor eax, eax
    mov al, [@@type]
    call addDynamicEntitytoArray, eax

    ; The index of the newly added entity is in free_index - 1
    mov al, [free_index]
    dec al  ; free_index points to the next free slot, so decrement to get the current entity index
    movzx eax, al  ; Zero-extend al to eax

    ; Pass the coordinates and entity index to updateDynamicCell
    mov bl, [@@x]
    mov cl, [@@y]
    call updateDynamicCell, ebx, ecx, eax

    ret

ENDP initializeDynamicEntity

; -------------------------------------------------------------------

PROC main
    sti                 ; Enable interrupts
    cld                 ; Clear direction flag

    push ds
    pop	es

    ;Set video mode to 13h
    ;call setVideoMode, 13h

    ;call updateCell, 0, 0, 5
    ;call printGrid, 7
    ;call moveCell, 0, 0, 10, 0
    ;call printGrid, 7

    ; test dynamic grid
    ;call addDynamicEntitytoArray, 1
    ;call printDynamicEntityState, 0
    call initializeDynamicEntity, 0, 0, 1
    call initializeDynamicEntity, 0, 1, 1
    call initializeDynamicEntity, 0, 2, 1
    call printGrid, 0, offset dynamic_grid
    call printDynamicEntityState, 0
    call printDynamicEntityState, 1

    ; Main game loop
gameLoop:

    ; Update game state and render frame
    ; ...
    
    ; if ESC pressed, exit the program
    call    checkForSpecificKeystroke, 001Bh
    jmp gameLoop
ENDP main

; -------------------------------------------------------------------
DATASEG

    STRUC ENTITY
        type    db -1
        health  db ?
        damage  db ?
        speed   db ?
        direction db ?
        animationFrame db ?
        animationTimer db ?
        spriteIndex db ?
    ENDS ENTITY

	palette		db 768 dup (?) ; 256 colors * 3 bytes per color
    grid        ENTITY 100 dup (<>)  ; 5 rows * 20 columns

    dynamic_grid db 100 dup (-1) ; 5 rows * 20 columns
    dynamic_entities_array ENTITY 100 dup (<>) ; make space for 100 entities
    free_index db 0 ; index of the first free entity in the dynamic_entities_array
    mob_capacity db 100 ; maximum number of entities in the dynamic_entities_array




    ; Template entity structure
    ; Structure of an entity:
    ; - 1 byte: type of entity (0 for plant, 1 for zombie, 2 for projectile, 3 for sun, 4 for lawn mower)
    ; - 1 byte: width (in pixels)
    ; - 1 byte: height (in pixels)
    ; - 1 byte: health (how much health the entity has)
    ; - 1 byte: damage (how much damage the entity deals if it's a projectile or a zombie, else 0 for potato, 1 for sunflower ...)
    ; - 1 byte: speed (determines entity's movement speed if direction is not 0, else it's the speed of the projectile)
    ; - 1 byte: direction (0 for no direction - which means that it doesn't move, 1 for left, 2 for right)
    ; - 1 byte: animation frame (if applicable)
    ; - 1 byte: animation timer (if applicable)
    ; - 1 byte: sprite index (if applicable)
    ; - 1 byte: render hierarchy (0 for background, 1 for entities, 2 for projectiles, 3 for UI)


; -------------------------------------------------------------------
; STACK
; -------------------------------------------------------------------
STACK 100h

END main
