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
COLUMNS EQU 9		; number of columns
BMP_HEADER_SIZE equ 54

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

; Check if a specific keystroke is pressed.
; If the specified key is pressed, exit the program.
; Otherwise, return.
PROC checkForSpecificKeystroke
    ARG     @@key:byte
    USES    eax, ebx, ecx, edx, esi, edi

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
    ARG @@x:BYTE, @@y:BYTE, @@value:BYTE, @@bias:BYTE, @@grid:DWORD
    USES eax, ebx, edi, esi

    ; Calculate the offset of the cell in the grid
    mov edi, [@@grid]
    movzx eax, [@@y]
    imul eax, COLUMNS
    movzx ecx, [@@bias]
    imul eax,  ecx; the size of the entity structure
    movzx ebx, [@@x]
    imul ebx, ecx ; the size of the entity structure
    add eax, ebx

    ; Set the value of the cell
    add edi, eax
    mov al, [@@value]
    stosb

    ret

ENDP updateCell

; function that displays state of an entity in the grid
PROC printStaticEntityState
    ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, esi

    ; Calculate the offset of the cell in the grid
    mov esi, offset grid
    movzx eax, [@@y]
    imul eax, COLUMNS
    imul eax, 8
    add al, [@@x]
    imul eax, 8
    add esi, eax
    lodsb

    ; Print the entity state - let's start with just the type
    add al, '0'
    mov ah, 0Eh
    int 10h

    ret

ENDP printStaticEntityState



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

; --------------------------------------------------------------------------------------------------------------------------------------

; functions for dynamic entities

; --------------------------------------------------------------------------------------------------------------------------------------

; function to get type of an entity
PROC getEntityType
    ARG @@x:BYTE, @@y:BYTE, @@grid:DWORD
    USES eax, ebx, ecx, edx, esi, edi, ebp, esp

        ; Calculate the offset of the cell in the grid
        mov esi, [@@grid]
        movzx eax, [@@y]
        imul eax, COLUMNS
        add al, [@@x]
        add esi, eax
        xor eax, eax
        lodsb ; this gives the index of the entity in the dynamic_entities_array

        ; Get the type of the entity
        mov esi, offset dynamic_entities_array
        add esi, eax
        xor eax, eax
        lodsb

        cmp al, -1
        je unknown_entity

        ; Print the type of the entity
        call printDecimal, eax

        ret

    unknown_entity:
        mov edx, offset msg_unknown
        mov ah, 09h
        int 21h

        ret

ENDP getEntityType

; function to initialize a dynamic entity
PROC initializeDynamicEntity
    ARG @@x:BYTE, @@y:BYTE, @@type:BYTE
    USES eax, ebx, ecx, edx, edi, esi, ebp, esp

            ; start with only adding the type - TODO add more properties

            ; first allocate space for the entity in the dynamic_entities_array
            ; secondly, set the type of the entity 
            ; thirdly, set the position of the entity in the dynamic_grid

            movzx eax, [free_index]
            mov edi, offset dynamic_entities_array
            add edi, eax
            xor eax, eax
            mov al, [@@type]
            stosb

            mov al, [free_index]
            mov bl, [@@type]
            mov cl, [@@x]
            mov dl, [@@y]
            call updateCell, ecx, edx, eax, 1, offset dynamic_grid

            inc [free_index]
            push eax
            mov edx, offset msg_type
            mov ah, 09h
            int 21h
            xor eax, eax
            pop eax
            call printDecimal, eax

            ret
ENDP initializeDynamicEntity

; --------------------------------------------------------------------------------------------------------------------------------------

PROC main
    sti                 ; Enable interrupts
    cld                 ; Clear direction flag

    push ds
    pop	es

    ;Set video mode to 13h
    ;call setVideoMode, 13h
    
    call initializeDynamicEntity, 8, 0, 1
    call initializeDynamicEntity, 8, 2, 1
    call initializeDynamicEntity, 7, 0, 2
    call initializeDynamicEntity, 4, 4, 10
    call printGrid, 0, offset dynamic_grid
    call getEntityType, 8, 0, offset dynamic_grid
    call getEntityType, 8, 2, offset dynamic_grid
    call getEntityType, 7, 0, offset dynamic_grid
    call getEntityType, 4, 4, offset dynamic_grid
    

   ; call fillBackgroundFaster, 93 ; fill the screen with white

    ; draw 50 * 200 rectangle, reserved space for UI
  ;  call drawColoredRectangle, 0, 0, 50, 200, 0 ; draw the left side of the screen

    ; Main game loop
gameLoop:

    ; Update game state and render frame
    ; ...
   ; call drawBackground ; draw the grid
    ;call drawPlant, 50, 0 ; draw a plant at position 10, 10
    ;call drawZombie, 290, 0 ; draw a zombie at position 100, 100
    ;call drawProjectile, 260, 0 ; draw a projectile at position 150, 150
  ;  call drawStaticEntitiesOnGrid, 7, offset grid ; draw the plants
   ; call drawStaticEntitiesOnGrid, 0, offset dynamic_grid ; draw the zombies and projectiles
    
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
    mob_counter db 0 ; number of entities in the dynamic_entities_array

    sprite db "test.bmp", 0
    buffer db BMP_HEADER_SIZE + 320 * 200 dup (0)

    msg_unknown db "Unknown entity type", 10, 13, "$"
    msg_type db "free index is", 10, 13, "$"

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
