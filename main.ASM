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
ROWS EQU 5 		; number of rows
COLUMNS EQU 9		; number of columns
BMP_HEADER_SIZE equ 54

; -------------------------------------------------------------------
CODESEG

; --------------------------------------------------------------------------------------------------------------------------------------

; functions for general purpose

; --------------------------------------------------------------------------------------------------------------------------------------

; wait for @@framecount frames
proc wait_VBLANK
	ARG @@framecount: word
	USES eax, ecx, edx
	mov dx, 03dah 					; Wait for screen refresh
	movzx ecx, [@@framecount]
	
		@@VBlank_phase1:
		in al, dx 
		and al, 8
		jnz @@VBlank_phase1
		@@VBlank_phase2:
		in al, dx 
		and al, 8
		jz @@VBlank_phase2
	loop @@VBlank_phase1
	
	ret 
endp wait_VBLANK

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

; function to print a character
PROC printChar
    ARG @@char:BYTE
    USES eax

    mov ah, 0Eh
    mov al, [@@char]
    int 10h

    ret

ENDP printChar

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

; function to print decimal without new line
PROC printDecimalWithoutNewLine
    ARG @@number:DWORD
    USES eax, ebx, ecx, edx

            mov	eax, [@@number]
            mov ebx, 10
            xor ecx, ecx

        getNextDigit_without_new_line:
            inc ecx
            xor edx, edx
            div ebx
            push dx ; store remainder on stack
            test eax, eax ; if zero, last digit
            jnz	getNextDigit_without_new_line

            mov ah, 02h
        printDigits_without_new_line:
            pop dx
            add dl, '0'
            int 21h
            loop printDigits_without_new_line

            call setCursorPosition, 4, 2

            ret

ENDP printDecimalWithoutNewLine

PROC setCursorPosition
    ARG @@row:BYTE, @@col:BYTE
    USES eax, ebx, ecx, edx

    mov ah, 02h     ;function to set cursor position
    mov bh, 00h     ;video page
    mov dh, [@@row] ;coordinates
    mov dl, [@@col]
    int 10h         ;set cursor position

    ret
ENDP setCursorPosition

; function to print decimal without new line
PROC printDecimalNoNewLine
    ARG @@number:DWORD
    USES eax, ebx, ecx, edx

            mov	eax, [@@number]
            mov ebx, 10
            xor ecx, ecx

        getNextDigitn:
            inc ecx
            xor edx, edx
            div ebx
            push dx ; store remainder on stack
            test eax, eax ; if zero, last digit
            jnz	getNextDigitn

            mov ah, 02h
        printDigitsn:
            pop dx
            add dl, '0'
            int 21h
            loop printDigitsn

            ret

ENDP printDecimalNoNewLine

; --------------------------------------------------------------------------------------------------------------------------------------

; functions for the grid

; --------------------------------------------------------------------------------------------------------------------------------------

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
        ;call printDecimal, al

    print_char:
        mov ah, 0Eh                     ; BIOS teletype function
        int 10h                         ; Call BIOS interrupt to print character
        ;call printDecimal, eax
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
        movzx ebx, [@@x]
        imul ebx, 8
        add eax, ebx
        add esi, eax
        mov ecx, 8
        
    get_values_loop_static:
        xor eax, eax
        lodsb
        call printDecimalNoNewLine, eax
        loop get_values_loop_static

        ret

ENDP printStaticEntityState

; function that returns the type of an entity in the grid
PROC getStaticEntityType
    ARG @@x:BYTE, @@y:BYTE RETURNS eax
    USES ebx, ecx, edx, esi

        ; Calculate the offset of the cell in the grid
        mov esi, offset grid
        movzx eax, [@@y]
        imul eax, COLUMNS
        imul eax, 8
        movzx ebx, [@@x]
        imul ebx, 8
        add eax, ebx
        add esi, eax
        xor eax, eax
        lodsb

        cmp al, -1
        je unknown_entity_static

        movzx eax, al

        ret

    unknown_entity_static:
        mov eax, 255

        ret

ENDP getStaticEntityType

; function that initializes a static entity
PROC initializeStaticEntity
    ARG @@x:BYTE, @@y:BYTE, @@type:BYTE
    USES eax, ebx, ecx, edx, esi

        movzx eax, [@@x]
        movzx ebx, [@@y]
        movzx ecx, [@@type]
        call updateCell, eax, ebx, ecx, 8, offset grid

        ret

ENDP initializeStaticEntity

; function to remove static entity from the grid
PROC removeStaticEntity
    ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, esi, edi

        ; update the type to -1 in the grid
        movzx eax, [@@x]
        movzx ebx, [@@y]
        call updateStaticEntityWithValue, eax, ebx, -1, 0

        ret

ENDP removeStaticEntity

; function to update static entity variables
PROC updateStaticEntityWithValues
    ARG @@x:BYTE, @@y:BYTE, @@health:BYTE, @@damage:BYTE, @@speed:BYTE, @@direction:BYTE, @@animationFrame:BYTE, @@animationTimer:BYTE, @@spriteIndex:BYTE
    USES eax, ebx, ecx, edx, edi, esi

        mov edi, offset grid
        movzx eax, [@@y]
        imul eax, COLUMNS
        imul eax, 8
        movzx ebx, [@@x]
        imul ebx, 8
        add eax, ebx
        add edi, eax
        inc edi ; skip the type

        mov al, [@@health]
        stosb

        mov al, [@@damage]
        stosb

        mov al, [@@speed]
        stosb

        mov al, [@@direction]
        stosb

        mov al, [@@animationFrame]
        stosb

        mov al, [@@animationTimer]
        stosb

        mov al, [@@spriteIndex]
        stosb

        ret

ENDP updateStaticEntityWithValues

; function to update one value of a static entity
PROC updateStaticEntityWithValue   
    ARG @@x:BYTE, @@y:BYTE, @@value:BYTE, @@offset:BYTE
    USES eax, ebx, ecx, edx, edi, esi

        mov edi, offset grid
        movzx eax, [@@y]
        imul eax, COLUMNS
        imul eax, 8
        movzx ebx, [@@x]
        imul ebx, 8
        add eax, ebx
        add edi, eax
        movzx eax, [@@offset]
        add edi, eax
        xor eax, eax

        mov al, [@@value]
        stosb

        ret

ENDP updateStaticEntityWithValue

; function to get the value of a static entity
PROC getValueOfStaticEntity
    ARG @@x:BYTE, @@y:BYTE, @@ofset:BYTE RETURNS eax
    USES ebx, ecx, edx, esi, edi

        ; get the health of the entity
        ; return the health of the entity in eax

        mov edi, offset grid
        movzx eax, [@@y]
        imul eax, COLUMNS
        imul eax, 8
        movzx ebx, [@@x]
        imul ebx, 8
        add eax, ebx
        add edi, eax
        mov cl, [@@ofset]
        add edi, ecx ; skip to the value needed 
        mov al, [edi]

        ret

ENDP getValueOfStaticEntity

; function to print the health of a static entity
PROC getDamageOfStaticEntity
    ARG @@x:BYTE, @@y:BYTE RETURNS eax
    USES ebx, ecx

        mov bl, [@@x]
        mov cl, [@@y]
        call getValueOfStaticEntity, ebx, ecx, 2 ; 2 is the offset of the damage value
        ; returns the damage of the entity in eax

        ret
ENDP getDamageOfStaticEntity

; function to inflic damage to a static entity and return the health in eax
PROC inflictDamageToStaticEntityFromArray
    ARG @@x:BYTE, @@y:BYTE, @@damage:BYTE RETURNS eax
    USES ebx, ecx, edx, edi, esi

        ; get the health of the entity
        ; subtract the damage from the health
        ; if the health is less than or equal to 0, remove the entity

        mov edi, offset grid
        movzx eax, [@@y]
        imul eax, COLUMNS
        imul eax, 8
        movzx ebx, [@@x]
        imul ebx, 8
        add eax, ebx
        add edi, eax
        inc edi ; skip the type
        mov al, [edi] ; load the health value
        sub al, [@@damage]
        mov [edi], al ; store the updated health value

        ; returns the health of the entity in eax
        movzx eax, al

        ret

ENDP inflictDamageToStaticEntityFromArray

; --------------------------------------------------------------------------------------------------------------------------------------

; functions for dynamic entities

; --------------------------------------------------------------------------------------------------------------------------------------

; Do memory management for dynamic entities
; TODO: count the amount of initialized entities and check if there is still space for a new entity to prevent overflow

; function to get type of an entity
PROC getEntityType
    ARG @@x:BYTE, @@y:BYTE, @@grid:DWORD RETURNS eax
    USES ebx, ecx, edx, esi, edi 

            xor eax, eax

            ; Calculate the offset of the cell in the grid
            mov esi, [@@grid]
            movzx eax, [@@y]
            imul eax, COLUMNS
            add al, [@@x]
            add esi, eax
            xor eax, eax
            lodsb ; this gives the index of the entity in the dynamic_entities_array

            cmp al, -1
            je unknown_entity

            movzx eax, al
            call getEntityFromArray, eax

            ret

        unknown_entity:
            mov eax, 255

            ret
ENDP getEntityType

; function to get entity given an index
PROC getEntityFromArray     
    ARG @@index:BYTE RETURNS eax
    USES esi

        xor eax, eax
        ; Get the type of the entity
        mov esi, offset dynamic_entities_array
        movzx eax, [@@index]
        imul eax, 8
        add esi, eax
        xor eax, eax
        lodsb

        cmp al, -1
        je unknown_entity_on_index
        movzx eax, al

        ret

    unknown_entity_on_index:
        mov eax, 255

        ret

ENDP getEntityFromArray

; function to print all entity member values given an index
PROC printDynamicEntityStateFromArray
    ARG @@index:BYTE, @@bias:BYTE, @@grid:DWORD
    USES eax, ebx, ecx, edx, edi, esi

            ; get the adress
            mov esi, [@@grid]
            movzx eax, [@@index]
            movzx ebx, [@@bias]
            imul eax, ebx
            add esi, eax
            movzx ecx, [@@bias]
        
        get_values_loop:
            lodsb
            call printDecimalNoNewLine, eax
            loop get_values_loop


            ret
ENDP printDynamicEntityStateFromArray

PROC incrementFreeIndex
    USES eax

        inc [free_index]
        cmp [free_index], 99
        jne no_reset
        mov [free_index], 0

    no_reset:

        ret
ENDP incrementFreeIndex

; function to initialize a dynamic entity
PROC initializeDynamicEntity
    ARG @@x:BYTE, @@y:BYTE, @@type:BYTE RETURNS eax
    USES ebx, ecx, edx, edi, esi

        find_free_position:
            xor eax, eax
            movzx eax, [free_index] ; get the current index and multiply it by the size of the entity structure, 8
            ;call printDecimal, eax
            call getEntityFromArray, eax
           ; call printDecimal, eax
            cmp eax, 255
            jne no_free_position
            jmp found_free_position

        no_free_position:
            call incrementFreeIndex
            jmp find_free_position

        found_free_position:
            mov edi, offset dynamic_entities_array
            movzx eax, [free_index] ; get the current index and multiply it by the size of the entity structure, 8
            imul eax, 8
            add edi, eax
            xor eax, eax
            mov al, [@@type]
            stosb

            mov al, [free_index]
            mov bl, [@@type]
            mov cl, [@@x]
            mov dl, [@@y]
            call updateCell, ecx, edx, eax, 1, offset dynamic_grid

            movzx eax, [free_index] ; return the index of the entity so it can be used in the main algorithm
            call incrementFreeIndex

            ret
ENDP initializeDynamicEntity

; function to get the value of a dynamic entity
PROC getValueOfDynamicEntity
    ARG @@index:BYTE, @@offset:BYTE RETURNS eax
    USES ebx, ecx, edx, esi, edi


        mov edi, offset dynamic_entities_array
        movzx eax, [@@index]
        imul eax, 8
        add edi, eax
        movzx ecx, [@@offset]
        add edi, ecx
        mov al, [edi] ; load the health value

        ret
ENDP getValueOfDynamicEntity

; function to get damage of a dynamic entity
PROC getDamageOfDynamicEntity
    ARG @@index:BYTE RETURNS eax

        movzx eax, [@@index]
        call getValueOfDynamicEntity, eax, 2 ; 2 is the offset of the damage value

        ret
ENDP getDamageOfDynamicEntity

; function to get damage of dynamic entity based on x and y
PROC getDamageOfDynamicEntityFromGrid
    ARG @@x:BYTE, @@y:BYTE RETURNS eax
    USES ebx, ecx

        mov esi, offset dynamic_grid
        movzx ebx, [@@y]
        imul ebx, COLUMNS
        add bl, [@@x]
        add esi, ebx
        lodsb

        call getDamageOfDynamicEntity, eax

        ret

ENDP getDamageOfDynamicEntityFromGrid

; function to get the health of a dynamic entity
PROC getHealthOfDynamicEntity
    ARG @@index:BYTE RETURNS eax

        movzx eax, [@@index]
        call getValueOfDynamicEntity, eax, 1 ; 1 is the offset of the health value

        ret

ENDP getHealthOfDynamicEntity

; function to get the health of a dynamic entity based on x and y
PROC getHealthOfDynamicEntityFromGrid
    ARG @@x:BYTE, @@y:BYTE RETURNS eax
    USES ebx, ecx

        mov esi, offset dynamic_grid
        movzx ebx, [@@y]
        imul ebx, COLUMNS
        add bl, [@@x]
        add esi, ebx
        lodsb

        call getHealthOfDynamicEntity, eax

        ret

ENDP getHealthOfDynamicEntityFromGrid

; function to updates one value given the value and the offset in the entity
PROC updateDynamicEntityWithValue 
    ARG @@index:BYTE, @@value:BYTE, @@offset:BYTE
    USES eax, ebx, ecx, edx, edi, esi

        mov edi, offset dynamic_entities_array
        movzx eax, [@@index]
        imul eax, 8
        add edi, eax
        movzx eax, [@@offset]
        add edi, eax
        xor eax, eax

        mov al, [@@value]
        stosb

        ret

ENDP updateDynamicEntityWithValue

; function that given an index and a type, sets the variables of the entity
PROC updateDynamicEntityWithValues
    ARG @@index:BYTE, @@health:BYTE, @@damage:BYTE, @@speed:BYTE, @@direction:BYTE, @@animationFrame:BYTE, @@animationTimer:BYTE, @@spriteIndex:BYTE
    USES eax, ebx, ecx, edx, edi, esi

        mov edi, offset dynamic_entities_array
        movzx eax, [@@index]
        imul eax, 8
        add edi, eax
        inc edi
        xor eax, eax

        mov al, [@@health]
        stosb

        mov al, [@@damage]
        stosb

        mov al, [@@speed]
        stosb

        mov al, [@@direction]
        stosb

        mov al, [@@animationFrame]
        stosb

        mov al, [@@animationTimer]
        stosb

        mov al, [@@spriteIndex]
        stosb

        ret

ENDP updateDynamicEntityWithValues

; function to remove an entity from the dynamic_grid and subsequently from the dynamic_entities_array
PROC removeDynamicEntity
    ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, edi, esi

        ; first get the index of the entity in the dynamic_entities_array
        ; then set the type of the entity to -1 in the dynamic_grid
        ; then set the type of the entity to -1 in the dynamic_entities_array

        movzx eax, [@@y]
        imul eax, COLUMNS
        add al, [@@x]
        mov esi, offset dynamic_grid
        add esi, eax
        lodsb
        
        xor edi, edi
        mov edi, offset dynamic_entities_array
        imul eax, 8
        add edi, eax
        xor eax, eax
        mov al, -1
        stosb

        movzx eax, [@@y]
        imul eax, COLUMNS
        add al, [@@x]
        mov edi, offset dynamic_grid
        add edi, eax
        mov al, -1
        stosb

        ret

ENDP removeDynamicEntity

; **UPDATE DAMAGE AND HEALTH**

; inflict damage to an entity from the dynamic_entities_array
PROC inflictDamageToDynamicEntityFromArray
    ARG @@index:BYTE, @@damage:BYTE
    USES ebx, ecx, edx, edi, esi

    ; get the health of the entity
    ; subtract the damage from the health
    ; if the health is less than or equal to 0, remove the entity

    xor eax, eax
    mov edi, offset dynamic_entities_array
    movzx eax, [@@index]
    imul eax, 8
    add edi, eax
    inc edi ; skip the type
    mov al, [edi] ; load the health value
    sub al, [@@damage]
    mov [edi], al ; store the updated health value

    ; returns the health of the entity in eax
    movzx eax, al

    ret
ENDP inflictDamageToDynamicEntityFromArray

; **UPDATE LOCATION OF DYNAMIC ENTITIES**

; function to move a value of a cell in the grid
PROC moveValue
    ARG @@x1:BYTE, @@y1:BYTE, @@x2:BYTE, @@y2:BYTE, @@bias:BYTE, @@grid:DWORD
    USES eax, ebx, ecx, edi, esi

        ; get the value of the first cell
        ; set the value of the second cell to the value of the first cell
        ; set the value of the first cell to -1

        ; Calculate the offset of the first cell in the grid
        mov esi, [@@grid]
        movzx eax, [@@y1]
        imul eax, COLUMNS
        movzx ecx, [@@bias]
        imul eax, ecx
        add al, [@@x1]
        imul eax, ecx
        mov ebx, eax
        add esi, eax
        lodsb
        push eax

        cmp eax, -1
        je no_move_value_needed
        
        mov edi, [@@grid]
        add edi, ebx
        mov al, -1
        stosb

        ; Calculate the offset of the second cell in the grid
        mov edi, [@@grid]
        movzx eax, [@@y2]
        imul eax, COLUMNS
        movzx ecx, [@@bias]
        imul eax, ecx
        add al, [@@x2]
        imul eax, ecx
        add edi, eax
        xor eax, eax
        pop eax
        stosb ; set the value of the second cell to the value of the first cell

    no_move_value_needed:

        ret
ENDP moveValue

; function that moves an entity in a certain direction
PROC moveEntityDirection
    ARG @@x:BYTE, @@y:BYTE, @@directionX:BYTE, @@directionY:BYTE, @@direction:BYTE, @@bias:BYTE, @@grid:DWORD
    USES eax, ebx, ecx, edx, edi, esi

        ; move (x, y) to (x + directionX, y + directionY)
        movzx eax, [@@x]
        movzx ebx, [@@y]
        movzx ecx, [@@x]
        movzx edx, [@@y]
        movzx edi, [@@bias]
        mov esi, [@@grid]
        cmp [@@direction], 0
        je move_entity_positive_direction

        sub cl, [@@directionX]
        sub dl, [@@directionY]
        jmp move_entity_call
        
    move_entity_positive_direction:
        add cl, [@@directionX]
        add dl, [@@directionY]
    move_entity_call:
        call moveValue, eax, ebx, ecx, edx, edi, esi      

        ret

ENDP moveEntityDirection

; function that moves an entity in the positive x direction only once
PROC moveEntityRight
    ARG @@x:BYTE, @@y:BYTE, @@bias:BYTE, @@grid:DWORD
    
    mov al, [@@x]
    mov bl, [@@y]
    movzx edi, [@@bias]
    mov esi, [@@grid]
    call moveEntityDirection, eax, ebx, 1, 0, 0, edi, esi

    ret

ENDP moveEntityRight

; function that moves an entity in the negative x direction only once
PROC moveEntityLeft
    ARG @@x:BYTE, @@y:BYTE, @@bias:BYTE, @@grid:DWORD
    
    mov al, [@@x]
    mov bl, [@@y]
    movzx edi, [@@bias]
    mov esi, [@@grid]
    call moveEntityDirection, eax, ebx, 1, 0, 1, edi, esi

    ret

ENDP moveEntityLeft

; --------------------------------------------------------------------------------------------------------------------------------------

; Game logic

; --------------------------------------------------------------------------------------------------------------------------------------

; get entity type
PROC getType
    ARG @@raw:BYTE RETURNS eax
    USES ebx

        ; type consits of two digits, first digit is type, which discriminates between zombies, plants and so on
        ; the second digit discriminates between different types of the same entity, for example, different types of zombies

        ; return the first digit of the type
        ; get the result by dividing the type by 10, the remainder is the second digit, we don't need it
        xor eax, eax
        mov al, [@@raw]
        cmp al, -1
        je unknown_entity_get_type
        cmp al, 255
        je unknown_entity_get_type
        mov bl, 10
        xor ah, ah
        div bl ; divide al by bl, result in al, remainder in ah

        ; returns the first digit of the type in eax
        movzx eax, al

        ret

    unknown_entity_get_type:
        mov eax, 255

        ret

ENDP getType

; **HEALTH AND DAMAGE**

; inflict damage to en entity from the dynamic_grid and remove the entity if the health is less than or equal to 0
PROC inflictDamageToDynamicEntityFromGrid
    ARG @@x:BYTE, @@y:BYTE, @@damage:BYTE
    USES eax, ebx, ecx, edx, edi, esi

            ; get the index of the entity in the dynamic_entities_array
            ; call inflictDamageToDynamicEntityFromArray with the index and the damage
            ; if the health is less than or equal to 0, remove the entity

            movzx eax, [@@y]
            imul eax, COLUMNS
            add al, [@@x]
            mov esi, offset dynamic_grid
            add esi, eax
            lodsb
            movzx ebx, [@@damage]
            call inflictDamageToDynamicEntityFromArray, eax, ebx

            cmp eax, 50
            jg remove_unvalid_entity
            cmp eax, 0
            jg no_remove_entity

        remove_unvalid_entity:
            ; remove the entity
            movzx eax, [@@x]
            movzx ebx, [@@y]
            call removeDynamicEntity, eax, ebx

        no_remove_entity:

            ret

ENDP inflictDamageToDynamicEntityFromGrid

; inflict damage to an entity from the static_grid and remove the entity if the health is less than or equal to 0
PROC inflictDamageToStaticEntityFromGrid
    ARG @@x:BYTE, @@y:BYTE, @@damage:BYTE
    USES eax, ebx, ecx, edx, esi, edi

        ; inflict damage to the entity
        ; if the health is less than or equal to 0, remove the entity

        movzx eax, [@@x]
        movzx ebx, [@@y]
        movzx ecx, [@@damage]
        call inflictDamageToStaticEntityFromArray, eax, ebx, ecx

        cmp eax, 0
        jg no_remove_entity_static

        ; remove the entity
        movzx eax, [@@x]
        movzx ebx, [@@y]
        call removeStaticEntity, eax, ebx

    no_remove_entity_static:
        ret


ENDP inflictDamageToStaticEntityFromGrid

; **MOVEMENT**
; has to go from right to left, top to bottom otherwise the entities will move in the wrong order

; function that handles movement of dynamic entities
PROC handleMovement
    ARG @@x:BYTE, @@y:BYTE RETURNS eax, ebx
    USES ecx, edx, edi, esi

            ; check if type of entity is valid
            ; if the type is valid, call handleProjectileMovement or handleZombieMovement
            ; return 1 if a zombie is moved
            ; else return 0

            ; return the type of the moved entity in ebx
            ; if zombie, return 1 else return 0
            xor eax, eax
            xor ebx, ebx

            mov al, [@@x]
            mov bl, [@@y]
            call getEntityType, eax, ebx, offset dynamic_grid
            call getType, eax 
            cmp al, 255
            je invalid_type_movement
            cmp al, -1
            je invalid_type_movement

            cmp al, 1
            je handle_zombie
            cmp al, 2
            je handle_projectile
            mov eax, 0
            mov ebx, 0
            ret

        handle_zombie:
            mov al, [@@x]
            call handleZombieMovement, eax, ebx
            ; returns 1 if a zombie is moved
            mov ebx, 1
            ret

        handle_projectile:
            mov al, [@@x]
            call handleProjectileMovement, eax, ebx
            mov eax, 0
            mov ebx, 0
            ret


        invalid_type_movement:
            mov eax, 0
            mov ebx, 0
            ret
        
ENDP handleMovement

; function that handles movement of projectiles
PROC handleProjectileMovement
    ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, edi, esi

            ; check if type of entity is valid
            ; if the type is valid, check if collision between projectile's position and position to its right
            ; if collision returns 0, move the projectile to the right
            ; if collision returns 1 -- should not happen
            ; if collision returns 2, remove the projectile and inflict damage to the entity
            xor eax, eax
            xor ebx, ebx

            mov al, [@@x]
            mov bl, [@@y]
            push eax
            call getEntityType, eax, ebx, offset dynamic_grid
            cmp al, 255
            jne checker
            ret

        checker:
            pop eax
            ; check if last column
            inc al
            cmp al, COLUMNS
            je remove_projectile_movement
        check_for_collision_type:
            ; check if collision with entity to the right
            mov al, [@@x]
            mov bl, [@@y]
            mov cl, al
            inc cl
            call collisionBetweenDynamicEntities, ecx, ebx, eax, ebx
            ;call printDecimal, eax
            cmp eax, 0
            je move_projectile_right
            cmp eax, 2
            je inflict_dmg
            ret

        move_projectile_right:
            xor eax, eax
            mov al, [@@x]
            call moveEntityRight, eax, ebx, 1, offset dynamic_grid
            ; After moving, check for collision again
            mov al, [@@x]
            mov bl, [@@y]
            mov cl, al
            inc cl
            call collisionBetweenDynamicEntities, ecx, ebx, eax, ebx
            cmp eax, 2
            je inflict_dmg
            ret

        inflict_dmg:
            movzx eax, [@@x]
            call getDamageOfDynamicEntityFromGrid, eax, ebx
            mov ecx, eax
            movzx eax, [@@x]
            inc eax
            call inflictDamageToDynamicEntityFromGrid, eax, ebx, 3 ; TODO: damage should be a variable
            jmp remove_projectile_movement

        remove_projectile_movement:
            mov al, [@@x]
            call removeDynamicEntity, eax, ebx
            ret

ENDP handleProjectileMovement

; function that handles movement of zombies
PROC handleZombieMovement
    ARG @@x:BYTE, @@y:BYTE RETURNS eax
    USES ebx, ecx, edx, edi , esi

            xor eax, eax
            mov al, [@@x]
            mov bl, [@@y]
            push eax
            call getEntityType, eax, ebx, offset dynamic_grid
            cmp al, 255
            jne checker_zombie
            ret

        checker_zombie:
            pop eax
            ; check if last column
            cmp al, 0
            je remove_zombie_movement

            ; check if collision with entity to the left
            mov al, [@@x]
            mov bl, [@@y]
            call collisionForHostileType, eax, ebx
            cmp eax, 0
            je move_zombie_left
            cmp eax, 2
            je inflict_dmg_zombie
            mov eax, 0
            ret

        move_zombie_left:
            xor eax, eax
            mov al, [@@x]
            call moveEntityLeft, eax, ebx, 1, offset dynamic_grid
            mov eax, 1
            ret

        inflict_dmg_zombie:
            movzx eax, [@@x]
            call getDamageOfDynamicEntityFromGrid, eax, ebx
            mov ecx, eax
            movzx eax, [@@x]
            dec eax
            call inflictDamageToStaticEntityFromGrid, eax, ebx, ecx ; TODO: damage should be a variable
            mov eax, 0
            ret

        remove_zombie_movement:
            mov al, [@@x]
            call removeDynamicEntity, eax, ebx
            mov eax, 0
            ret

ENDP handleZombieMovement

; **COLLISION DETECTION**

; function that combines the collision detection functions for dynamic entities of hostile type
PROC collisionForHostileType
    ARG @@x:BYTE, @@y:BYTE RETURNS eax
    USES ebx, ecx, edx, edi, esi

    ; check for collision between x, y and x - 1, y
    ; call collisionBetweenDynamicEntities with the two positions first
    ; if return value is 1, do nothing so return 1
    ; if return value is 2, should not happen
    ; if return value is 0, the space is not occupied in the dynamic_grid, check if it is occupied in the static_grid

    ; call collisionBetweenStaticAndDynamicEntities with (x1, y1) as the (x - 1, y) and (x2, y2) as the (x, y)
    ; if it returns 0, return 0, so the space is not occupied in the static_grid
    ; if it returns 2, the space is occupied, return 2

    ; summarized:
    ; return 0 means space not occupied
    ; return 1 means space occupied by friendly entity
    ; return 2 means space occupied by hostile entity

        mov al, [@@x]
        mov bl, [@@y]
        mov cl, al
        sub cl, 1
        push eax
        call collisionBetweenDynamicEntities, ecx, ebx, eax, ebx
        cmp eax, 1
        je friendly_entity
        cmp eax, 0
        je check_static_grid
        ret

    friendly_entity:
        pop eax
        mov eax, 1
        ret

    check_static_grid:
        pop eax
        call collisionBetweenStaticAndDynamicEntities, ecx, ebx, eax, ebx
        ret

ENDP collisionForHostileType

; function that checks if two positions in the dynamic_grid have the same type
PROC collisionBetweenDynamicEntities
    ARG @@x1:BYTE, @@y1:BYTE, @@x2:BYTE, @@y2:BYTE RETURNS eax
    USES ebx, ecx, edx, edi, esi

            ; return 2 if the two entities have different types that are valid
            ; return 1 if the two entities have the same type
            ; return 0 otherwise, so one of the two entities is invalid, or just empty (that is the same as invalid)
            ; which is useful for collision detection
            ; - collision of the same type means that they do not move into each other
            ; - collision of different type means that the projectile hits the zombie

            mov al, [@@x1]
            mov bl, [@@y1]
            call getEntityType, eax, ebx, offset dynamic_grid
            call getType, eax ; get rid of the second digit
            movzx ecx, al ; type of first entity in cl
            mov al, [@@x2]
            mov bl, [@@y2]
            call getEntityType, eax, ebx, offset dynamic_grid
            call getType, eax
            ; type of second entity in al
            cmp al, 255
            je invalid_entity
            cmp cl, 255
            je invalid_entity
            cmp al, cl
            je same_type
            jmp different_type

        invalid_entity:
            mov eax, 0
            ret

        same_type:
            mov eax, 1
            ret

        different_type:
            mov eax, 2
            ret       

ENDP collisionBetweenDynamicEntities

; function that checks if two positions, one of which is in the dynamic_grid and the other in the static_grid, have the same type
PROC collisionBetweenStaticAndDynamicEntities
    ARG @@x2:BYTE, @@y2:BYTE, @@x1:BYTE, @@y1:BYTE RETURNS eax
        USES ebx, ecx, edx, edi, esi

            ; return 2 if the two entities have types that are valid
            ; return 1 if the two entities have the same type - won't happen
            ; return 0 otherwise, so one of the two entities is invalid, or just empty (that is the same as invalid)
            ; x1, y1 is the dynamic entity, x2, y2 is the static entity

            mov al, [@@x1]
            mov bl, [@@y1]
            call getEntityType, eax, ebx, offset dynamic_grid
            call getType, eax ; get rid of the second digit
            movzx ecx, al ; type of first entity in cl
            mov al, [@@x2]
            mov bl, [@@y2]
            call getStaticEntityType, eax, ebx
            call getType, eax
            ; type of second entity in al
            cmp al, 255
            je invalid_entity_static
            cmp cl, 255
            je invalid_entity_static
            cmp al, cl
            je same_type
            jmp different_type_static

        invalid_entity_static:
            mov eax, 0
            ret

        same_type_static:
            mov eax, 1
            ret

        different_type_static:
            mov eax, 2
            ret

ENDP collisionBetweenStaticAndDynamicEntities

; **SPAWNING**
; functions to spawn entities at a given position, equiped with the right values

; function to handle spawning a projectile at a given position
PROC handleProjectileSpawning
    ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, edi, esi

        ; check if the position is valid or a potato
        ; if the position is valid, spawn a projectile at the position

        movzx eax, [@@x]
        movzx ebx, [@@y]
        call getStaticEntityType, eax, ebx
        cmp al, 255
        je invalid_entity_spawn_projectiles
        cmp al, -1
        je invalid_entity_spawn_projectiles
        cmp al, 9
        je invalid_entity_spawn_projectiles
        movzx eax, [@@x]
        call spawnProjectile, eax, ebx

        ret

    invalid_entity_spawn_projectiles:
        ret

ENDP handleProjectileSpawning

; function to spawn projectile at a given position, inherits the damage of the entity that spawned it
PROC spawnProjectile
    ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, edi, esi

            ; check if the plant at position is valid
            movzx eax, [@@x]
            movzx ebx, [@@y]
            call getStaticEntityType, eax, ebx
            call getType, eax
            cmp al, 255
            je invalid_entity_spawn_projectile
            cmp al, -1
            je invalid_entity_spawn_projectile
            cmp al, 0
            je spawn_the_projectile

        invalid_entity_spawn_projectile:
            ret

        spawn_the_projectile:
            movzx eax, [@@x]
            movzx ebx, [@@y]
            call getDamageOfStaticEntity, eax, ebx
            mov edx, eax
            movzx ecx, [@@x]
            call initializeDynamicEntity, ecx, ebx, 20
            call updateDynamicEntityWithValues, eax, 20, edx, 1, 0, 0, 0, 0

            ret

ENDP spawnProjectile

; function to spawn potato at a given position
PROC spawnPotato
ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, edi, esi

        ; spawn a plant at the given position with default values

        movzx eax, [@@x]
        movzx ebx, [@@y]
        call initializeStaticEntity, eax, ebx, 9
        call updateStaticEntityWithValues, eax, ebx, 10, 0, 1, 0, 0, 0, 0 ; a potato does not have damage, means that it can not spawn a projectile

        ret
ENDP spawnPotato

; function to spawn zombie at a given position
PROC spawnDefaultZombie
    ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, edi, esi

        ; spawn a zombie at the given position with default values

        movzx eax, [@@x]
        movzx ebx, [@@y]
        call initializeDynamicEntity, eax, ebx, 10
        ; returns the index of the entity in eax
        call updateDynamicEntityWithValues, eax, 10, 2, 1, 0, 0, 0, 0

        ret

ENDP spawnDefaultZombie

; function to spawn plant at a given position
PROC spawnDefaultPlant
    ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, edi, esi

        ; spawn a plant at the given position with default values

        movzx eax, [@@x]
        movzx ebx, [@@y]
        call initializeStaticEntity, eax, ebx, 0
        call updateStaticEntityWithValues, eax, ebx, 5, 3, 1, 0, 0, 0, 0

        ret

ENDP spawnDefaultPlant

; ** MAIN ALGORITHM **

; main algorithm that updates the game state
PROC updateGameState
    LOCAL @@currentY:BYTE, @@SpawnProjectile:BYTE ; 1 if projectile should be spawned
    USES eax, ebx, ecx, edx, edi, esi
        
            ; iterate over rows
            ; iterate over columns, from right to left
            ; call handleMovement for each entity

            mov ecx, ROWS 
            mov edx, COLUMNS
            dec edx

        outer_loop_update_game_state:
            push ecx
            mov ecx, edx
            mov [@@SpawnProjectile], 0
        
        inner_loop_update_game_state:
            ; call handleMovement for each entity
            ; x = current column (goes from right to left)
            ; y = ROWS - current row
            mov eax, ecx ; save ecx
            pop ecx ; get the row
            mov ebx, ROWS
            sub ebx, ecx ; ROWS - current row
            push ecx ; put the row back
            mov ecx, eax ; restore ecx
            mov [@@currentY], bl
            call handleMovement, ecx, ebx 
            ; returns how many cells to skip in eax, to prevent double movement
            ; returns the type of the entity in ebx
            sub ecx, eax
            ; check if a projectile should be spawned
            cmp [@@SpawnProjectile], 1
            je spawn_the_projectile_on_position
            ; if the entity moved is zombie, set @@SpawnProjectile to 1
            cmp ebx, 1
            je set_spawn_projectile

        after_checking_local:
            cmp ecx, 0
            je after_inner_loop_update_game_state
            dec ecx
            jmp inner_loop_update_game_state

        spawn_the_projectile_on_position:
            movzx ebx, [@@currentY]
            call handleProjectileSpawning, ecx, ebx
            jmp after_checking_local

        set_spawn_projectile:
            ;call printDecimal, 99
            mov [@@SpawnProjectile], 1 ; set @@SpawnProjectile to 1
            jmp after_checking_local

        after_inner_loop_update_game_state:
            pop ecx
            loop outer_loop_update_game_state
            
            ret

ENDP updateGameState

; --------------------------------------------------------------------------------------------------------------------------------------

; functions for graphics

; --------------------------------------------------------------------------------------------------------------------------------------

; state of the game = state of the grid + state of the entities
; - print out the grid
; - print out the plants
; - print out the zombies and projectiles

; First step: (naive)
; - function that prints the whole state

; Second step: (more optimal)
; - function that updates the state, for example, moves the entities, checks for collisions, etc.
; - this function needs to print only the entities that have changed, so only the cells that have changed
; - make this function have a parameters that specify which cell to update, this way, 
;   whenever a function that changes the game state is called, it can call this function with the changed cell

; Draw State:
; - draw level 0 (background) - draw the grid
; - draw level 1 (static entities) - draw the plants
; - draw level 2 (dynamic entities) - draw the zombies and projectiles

; function to draw the dynamic entities on the grid
PROC drawDynamicEntitiesOnGrid
    ARG @@bias:BYTE, @@grid:DWORD
    LOCAL @@type:BYTE
    USES eax, ebx, ecx, edx, edi, esi

    ; iterate over the grid, for each cell get the entity type
    ; if the entity type is valid, draw the entity of the given type

    mov esi, [@@grid]               ; Set ESI to point to the grid array
    mov ecx, ROWS
    mov edx, COLUMNS

    outer_loop_draw_entities:
        push ecx
        mov ecx, edx
    
    inner_loop_draw_entities:
        lodsb
        mov [@@type], al
        mov bl, [@@bias]
        add esi, ebx
        cmp al, -1
        je after_draw_dynamic_entity
        ; ADD HERE further types of entities
        jmp draw_dynamic_entity

    draw_dynamic_entity:
        ; x = (columns - ecx) * 30 + 50
        ; y = (rows - TOS) * 40
        mov eax, ecx ; save ecx
        pop ecx ; get the row
        mov ebx, ROWS
        sub ebx, ecx
        imul ebx, 40
        push ecx ; put the row back
        mov ecx, eax ; restore ecx
        mov eax, COLUMNS
        sub eax, ecx
        imul eax, 30
        add eax, 50
        push ecx
        mov ecx, eax
        movzx eax, [@@type]
        call getEntityFromArray, eax
        
        call drawEntity, ecx, ebx, eax
        pop ecx
        jmp after_draw_dynamic_entity

    after_draw_dynamic_entity:
        loop inner_loop_draw_entities
    
        pop ecx
        loop outer_loop_draw_entities
    
        ret
ENDP drawDynamicEntitiesOnGrid

; function to draw the static entities on the grid
PROC drawStaticEntitiesOnGrid
    ARG @@bias:BYTE, @@grid:DWORD
    LOCAL @@type:BYTE
    USES eax, ebx, ecx, edx, edi, esi

    ; Iterate over the grid, for each cell, check if there is a plant
    ; If there is a plant, draw the plant, read the type of the plant from the grid
    ; TODO make code better, too much repetition

    mov esi, [@@grid]               ; Set ESI to point to the grid array
    mov ecx, ROWS
    mov edx, COLUMNS

    outer_loop_draw_plants:
        push ecx
        mov ecx, edx

    inner_loop_draw_plants:
        lodsb
        mov [@@type], al
        mov bl, [@@bias]
        add esi, ebx
        cmp al, 0
        je draw_plant_entity
        ; ADD HERE further types of plants
        jmp after_draw_entity

    draw_plant_entity:
        
        ; x = (columns - ecx) * 30 + 50
        ; y = (rows - TOS) * 40
        mov eax, ecx ; save ecx
        pop ecx ; get the row
        mov ebx, ROWS
        sub ebx, ecx
        imul ebx, 40
        push ecx ; put the row back
        mov ecx, eax ; restore ecx
        mov eax, COLUMNS
        sub eax, ecx
        imul eax, 30
        add eax, 50
        push ecx
        movzx ecx, [@@type]
        
        call drawEntity, eax, ebx, 9
        pop ecx
        jmp after_draw_entity
    
    after_draw_entity:
        loop inner_loop_draw_plants
        
        pop ecx
        loop outer_loop_draw_plants

        ret
ENDP drawStaticEntitiesOnGrid

; function to draw an entity, given a type
PROC drawEntity
    ARG @@x0:word, @@y0:word, @@type: byte
    USES eax, ebx, ecx, edx, edi

        ; check the type of the entity
        ; draw the entity based on the type

        movzx eax, [@@type] ; TODO make switch case
        cmp al, 0
        je draw_plant
        cmp al, 9
        je draw_plant
        cmp al, 10
        je draw_zombie
        cmp al, 20
        je draw_projectile
        ret
    
    draw_plant:
        movzx ebx, [@@x0]
        movzx ecx, [@@y0]
        call drawPlant, ebx, ecx
        ret
    
    draw_zombie:
        movzx ebx, [@@x0]
        movzx ecx, [@@y0]
        call drawZombie, ebx, ecx
        ret
    
    draw_projectile:
        movzx ebx, [@@x0]
        movzx ecx, [@@y0]
        call drawProjectile, ebx, ecx
        ret

ENDP drawEntity

; function to draw a plant -- temporary, later on we will use sprites
PROC drawPlant
    ARG 	@@x0:word, @@y0:word
    USES 	eax, ebx, ecx, edx, edi

        ; draw 2 rectangles for the plant
        ; one for the stem and one for the head

        ; draw the stem
        mov ax, [@@x0]
        add eax, 13
        mov bx, [@@y0]
        add ebx, 20
        call drawColoredRectangle, eax, ebx, 4, 19, 42 ; draw the stem

        ; draw the head
        mov ax, [@@x0]
        add eax, 10
        mov bx, [@@y0]
        add ebx, 10
        call drawColoredRectangle, eax, ebx, 10, 10, 45 ; draw the head

        ret

ENDP drawPlant

; draw zombie
PROC drawZombie
    ARG 	@@x0:word, @@y0:word
    USES eax, ebx, ecx, edx, edi

    ; draw the head
    mov ax, [@@x0]
    add eax, 10
    mov bx, [@@y0]
    add ebx, 10
    call drawColoredRectangle, eax, ebx, 10, 10, 6

    ; draw the body
    mov ax, [@@x0]
    add eax, 12
    mov bx, [@@y0]
    add ebx, 20
    call drawColoredRectangle, eax, ebx, 6, 12, 4

    ; draw the legs
    mov ax, [@@x0]
    add eax, 13
    mov bx, [@@y0]
    add ebx, 32
    call drawColoredRectangle, eax, ebx, 4, 7, 55

    ret

ENDP drawZombie

; draw projectile
PROC drawProjectile
    ARG 	@@x0:word, @@y0:word
    USES eax, ebx, ecx, edx, edi

    ; draw a rectangle for the projectile
    mov ax, [@@x0]
    add eax, 10
    mov bx, [@@y0]
    add ebx, 20
    call drawColoredRectangle, eax, ebx, 10, 5, 21

    ret

ENDP drawProjectile

; function to draw the grid
; call for every cell draw rectangle
PROC drawBackground
    USES eax, ebx, ecx, edx, edi

    mov eax, 50 ; x offset
    mov ebx, 0 ; y offset
    mov ecx, ROWS ; number of rows
    mov edx, COLUMNS ; number of columns

    outer_loop_draw_background:
        push ecx ; save outer loop counter
        mov ecx, edx ; set inner loop counter

    inner_loop_draw_background:
        call drawRectangle, eax, ebx, 30, 40, 2 ; draw a rectangle at the current position
        add eax, 30 ; move to the next column
        loop inner_loop_draw_background ; repeat for each column

        mov eax, 50
        add ebx, 40 ; move to the next row
        pop ecx ; restore outer loop counter
        loop outer_loop_draw_background ; repeat for each row<

        ret
ENDP drawBackground

; ** generic functions for drawing **

; Draw a rectangle (video mode 13h)
; 	* draws the rectangle from position (x0,y0) with
;	  positive width 'w' and height 'h', with color "col"
PROC drawRectangle
	ARG 	@@x0:word, @@y0:word, @@w:word, @@h:word, @@col: byte
	USES 	eax, ecx, edx, edi 

	; Compute the index of the rectangle's top left corner
	movzx eax, [@@y0]
	mov edx, SCRWIDTH
	mul edx
	add	ax, [@@x0]

	; Compute top left corner address
	mov edi, VMEMADR
	add edi, eax
	
	; Plot the top horizontal edge.
	movzx edx, [@@w]	; store width in edx for later reuse
	mov	ecx, edx
	mov	al,[@@col]
	rep stosb
	sub edi, edx		; reset edi to left-top corner
	
	; plot both vertical edges
	movzx ecx,[@@h]
	@@vertLoop:
		mov	[edi],al		; left edge
		mov	[edi+edx-1],al	; right edge
		add	edi, SCRWIDTH
		loop @@vertLoop
	; edi should point at the bottom-left corner now
	sub edi, SCRWIDTH

	; Plot the bottom horizontal edge.
	mov	ecx, edx
	rep stosb
	ret
ENDP drawRectangle

; Draw a colored rectangle (video mode 13h)
; 	* draws the rectangle from position (x0,y0) with
;	  positive width 'w' and height 'h', with color "col"
PROC drawColoredRectangle
    ARG 	@@x0:word, @@y0:word, @@w:word, @@h:word, @@col: byte
    USES 	eax, ecx, edx, edi ; note: MUL uses edx!

    ; Compute the index of the rectangle's top left corner
    movzx eax, [@@y0]
    mov edx, SCRWIDTH
    mul edx
    add	ax, [@@x0]

    ; Compute top left corner address
    mov edi, VMEMADR
    add edi, eax
    
    ; Fill the rectangle
    movzx edx, [@@w]	; store width in edx for later reuse
    mov	al,[@@col]
    movzx ecx, [@@h]	; store height in ecx for loop
    @@fillLoop:
        push ecx			; save height counter
        mov ecx, edx		; set width counter
        rep stosb			; fill one row
        pop ecx				; restore height counter
        add edi, SCRWIDTH	; move to the next row
        sub edi, edx		; reset edi to the start of the next row
        loop @@fillLoop

    ret
ENDP drawColoredRectangle

; Fill the background (for mode 13h) faster
; (uses stosd optimization)
;	* fillcolor: input color
PROC fillBackgroundFaster
	ARG 	@@fillcolor:byte
	USES 	eax, ecx, edi

	; Initialize video memory address.
	mov	edi, VMEMADR
	
	; copy color value across all bytes of eax
	mov al, [@@fillcolor]	; ???B
	mov ah, al				; ??BB
	mov cx, ax			
	shl eax, 16				; BB00
	mov ax, cx				; BBBB

	; Scan the whole video memory and assign the background colour.
	mov	ecx, SCRWIDTH*SCRHEIGHT/4
	rep	stosd

	ret
ENDP fillBackgroundFaster

; --------------------------------------------------------------------------------------------------------------------------------------

PROC main
    sti                 ; Enable interrupts
    cld                 ; Clear direction flag

    push ds
    pop	es

    ;Set video mode to 13h
    call setVideoMode, 13h
    
    call spawnDefaultZombie, 8, 0
    call spawnDefaultZombie, 8, 1
    call spawnDefaultZombie, 8, 2
    call spawnDefaultZombie, 8, 3
    call spawnDefaultZombie, 8, 4

    call spawnDefaultPlant, 0, 0
    call spawnDefaultPlant, 0, 1
    call spawnDefaultPlant, 0, 2
    call spawnDefaultPlant, 0, 3
    call spawnDefaultPlant, 0, 4

    ;call handleMovement, 3, 0
    ;call updateGameState
    ;call updateGameState
    ;call printDynamicEntityStateFromArray, 1, 8, offset dynamic_entities_array

    ;call moveValue, 0, 0, 7, 0, 1, offset dynamic_grid
    ;call moveValue, 2, 2, 3, 1, 1, offset dynamic_grid
    ;call fillBackgroundFaster, 93 ; fill the screen with white
    ;call drawColoredRectangle, 0, 0, 50, 200, 0 ; draw the left side of the screen

    ; draw 50 * 200 rectangle, reserved space for UI
    ;call printGrid, 0, offset dynamic_grid ; print the grid to the screen

    ; Main game loop
gameLoop:

    ; Update game state and render frame
    call updateGameState

    call wait_VBLANK, 30 ; wait for the next frame
    call fillBackgroundFaster, 93 ; fill the screen with white
    ;call getHealthOfDynamicEntityFromGrid, 4, 0
    ;call printDecimalWithoutNewLine, eax
    call drawBackground ; draw the grid
    ;call drawColoredRectangle, 0, 0, 50, 200, 0 ; draw the left side of the screen
    ;call drawPlant, 50, 0 ; draw a plant at position 10, 10
    ;call drawZombie, 290, 0 ; draw a zombie at position 100, 100
    ;call drawProjectile, 260, 0 ; draw a projectile at position 150, 150
    call drawStaticEntitiesOnGrid, 7, offset grid ; draw the plants
    call drawDynamicEntitiesOnGrid, 0, offset dynamic_grid ; draw the zombies and projectiles
    
    
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
