; -------------------------------------------------------------------
; 80386
; 32-bit x86 assembly language
; TASM
;
; authors:	Tugay ülger, Vojtech De Coninck
; date:		23/12/2024
; program:	Video mode 13h
; -------------------------------------------------------------------

IDEAL
P386
MODEL FLAT, C
ASSUME cs:_TEXT,ds:FLAT,es:FLAT,fs:FLAT,gs:FLAT

; compile-time constants (with macros)
VMEMADR EQU 0A0000h	; video memory address
SCRWIDTH EQU 320	; screen width
SCRHEIGHT EQU 200	; screen height
ROWS EQU 5 		; number of rows
COLUMNS EQU 10		; number of columns
VISIBLE_COLUMNS EQU 9 ; number of columns that are visible
BMP_HEADER_SIZE equ 54 ; size of BMP header

SPRITEWIDTH EQU 30 ; width of sprite
SPRITEHEIGHT EQU 40 ; height of sprite
DATASIZE EQU SPRITEWIDTH*SPRITEHEIGHT ; bytes of data in file
BUTTONWIDTH EQU 25 ; width of button
BUTTONHEIGHT EQU 33 ; height of button
BUTTONSIZE EQU BUTTONWIDTH*BUTTONHEIGHT ; size of button

TILE_WIDTH EQU 30 ; width of a tile
TILE_HEIGHT EQU 40 ; height of a tile
SHOP_WIDTH EQU 50 ; width of the shop area
NUM_REGIONS EQU 7 ; number of regions

FIRETIMER EQU 25 ; fire timer value
FIREINTERVAL EQU 100 ; fire interval value
ENTITY_SIZE EQU 12 ; size of an entity
ENTITY_BIAS EQU 11 ; entity bias value
MAX_ENTITIES EQU 100 ; maximum number of entities
SPAWN_INTERVAL EQU 100 ; spawn interval value
LEVELS_COUNT EQU 8 ; number of levels

SB_BASE equ 220h ; Sound Blaster base address
SB_IRQ equ 7 ; Sound Blaster IRQ
SB_DMA equ 1 ; Sound Blaster DMA channel
INT_NUMBER equ 0fh ; interrupt number
SND_BUFF_SIZE EQU 8192 ; sound buffer size
LOOPING_AUDIO_LENGTH EQU 52 ; length of looping audio

RAND_A = 1103515245 ; multiplier for random number generator
RAND_C = 12345 ; increment for random number generator

UDATASEG
    rand_seed   dd ? ; random seed
    buffer_start dd ? ; buffer start address
    sound_buffer db 2 * SND_BUFF_SIZE dup (?) ; sound data buffer
    sndhandle dw ? ; sound handle

; -------------------------------------------------------------------

CODESEG

; --------------------------------------------------------------------------------------------------------------------------------------
; RAND.ASM


;+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
; Initialize the random number generator.
;
; ARGUMENTS:
;   none
; RETURNS:
;   nothing
;+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
PROC rand_init
    USES    eax, ecx, edx

    mov     ah, 02ch        ; Get system time
    int     21h

    mov     ax, dx          ; Use time to generate seed in EAX
    shl     eax, 16
    mov     ax, cx

    mov     ah, 02ah        ; Get system date
    int     21h

    shl     ecx, 16         ; Mangle date into the seed in EAX
    mov     cx, dx
    xor     eax, ecx
    
    mov     [rand_seed], eax

    ret
ENDP rand_init

;+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
; Returns the next (pseudo) random number in EAX.
;
; ARGUMENTS:
;   none
; RETURNS:
;   EAX     Random 32-bit value
;+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
PROC rand
    USES    ebx, ecx, edx

    mov     eax, [rand_seed]
    mov     ecx, RAND_A
    mul     ecx
    add     eax, RAND_C
    mov		ebx, eax
	shr		ebx, 16
	
	mul		ecx
	add     eax, RAND_C
	mov     [rand_seed], eax
	mov		ax, bx

    ret
ENDP rand

;+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
; Returns the next (pseudo) random number in AX.
;
; ARGUMENTS:
;   none
; RETURNS:
;   EAX     Random 16-bit value
;+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
PROC rand16
    USES    edx

    mov     eax, [rand_seed]
    mov     edx, RAND_A
    mul     edx
    add     eax, RAND_C
    mov     [rand_seed], eax
	shr		eax, 16
	
    ret
ENDP rand16

; function to generate a random number between 0 and 4
PROC rand5
    ARG RETURNS eax
    USES    ebx, edx

    call rand16
    mov ebx, 5
    xor edx, edx
    div ebx
    movzx eax, dx

    ret

ENDP rand5

; --------------------------------------------------------------------------------------------------------------------------------------

; functions for general purpose

; --------------------------------------------------------------------------------------------------------------------------------------

; function given a x calculates the pixel position, the right side of the entity
PROC convertXtoPixelPosition
    ARG @@x:BYTE RETURNS eax
    USES ebx, ecx, edx, esi, edi

    xor eax, eax
    mov al, [@@x]
    mov bl, 30
    mul bl ; multiply x by 30
    add eax, 50 ; offset of the left side of the screen
    add eax, 30 ; get the right side of the entity
    ret

ENDP convertXtoPixelPosition

; Function to convert screen coordinates to grid coordinates
PROC convertScreenCoordsToGridCoords
    ARG @@posX:DWORD, @@posY:DWORD RETURNS eax, ebx ; eax = gridX, ebx = gridY
    USES ecx, edx

    ; Calculate gridY = posY / TILE_HEIGHT
    mov eax, [@@posY]
    xor edx, edx
    mov ecx, TILE_HEIGHT
    div ecx

    cmp eax, ROWS
    jge gridY_out_of_bounds
    mov ebx, eax ; gridY = eax

    ; Check if posX is within the field
    mov eax, [@@posX]
    cmp eax, SHOP_WIDTH
    jl position_in_shop_area

    sub eax, SHOP_WIDTH ; adjustedX = posX - SHOP_WIDTH

    xor edx, edx
    mov ecx, TILE_WIDTH
    div ecx

    cmp eax, COLUMNS
    jge gridX_out_of_bounds

    ; gridX is in eax, gridY in ebx
    ret

position_in_shop_area:
    mov eax, 255
    mov ebx, 255
    ret

gridX_out_of_bounds:
    mov eax, 255
    mov ebx, 255
    ret

gridY_out_of_bounds:
    mov eax, 255
    mov ebx, 255
    ret

ENDP convertScreenCoordsToGridCoords

; Function to convert grid coordinates to pixel position
PROC convertGridCoordsToPixelPosition
    ARG @@gridX:DWORD, @@gridY:DWORD RETURNS eax, ebx ; eax = pixelX, ebx = pixelY
    USES ecx, edx

    ; Calculate pixelX = gridX * TILE_WIDTH + SHOP_WIDTH
    mov eax, [@@gridX]
    imul eax, TILE_WIDTH
    add eax, SHOP_WIDTH

    ; Calculate pixelY = gridY * TILE_HEIGHT
    mov ebx, [@@gridY]
    imul ebx, TILE_HEIGHT

    ret
ENDP convertGridCoordsToPixelPosition

; function to check if x is on the boundary of the next cell
PROC checkIfXIsOnBoundary
        ARG @@x:BYTE RETURNS eax, ebx ; eax is the x, ebx is whether it passed the boundary
        USES ecx, edx, esi, edi

        xor eax, eax
        xor ebx, ebx
        movzx eax, [@@x]
        cmp eax, 0
        je x_is_freshly_on_boundary

        cmp eax, 30
        jl still_within_cell

        ; if greater than 30, x is on the boundary or outside the cell
        mov ebx, 1

        ret

    still_within_cell:
        mov ebx, 0

        ret

    x_is_freshly_on_boundary: ; skip the division if x is freshly on the boundary
        mov eax, 1

        ret

ENDP checkIfXIsOnBoundary

PROC  startTime
    USES eax,ebx,ecx, edx, esi, edi

    mov ah, 2Ch
    int 21h

    movzx eax, ch
    imul eax, 3600
    movzx ebx, cl
    imul ebx, 60
    add eax, ebx
       
    movzx edx, dh
    add eax, edx

    mov [start_time], eax ;set start_time to current time

    ret
ENDP startTime

PROC setElapsedTime
    USES eax, ebx, ecx, edx, esi, edi
    
    mov ah, 2Ch
    int 21h

    movzx eax, ch
    imul eax, 3600
    movzx ebx, cl
    imul ebx, 60
    add eax, ebx
       
    movzx edx, dh
    add eax, edx
    
    sub eax, [start_time]
    mov [elapsed_time], eax

    ret
ENDP setElapsedTime

PROC checkAndResetTimer
    USES eax, ebx, ecx, edx, esi, edi

        ; Calculate the elapsed time
        call setElapsedTime

        ; Load the elapsed time into eax
        mov eax, [elapsed_time]

        ; Check if the elapsed time is equal to 52
        cmp eax, LOOPING_AUDIO_LENGTH
        jne continue

        ; If equal to 52, reset the timer
        call startTime
        call stopMusic
        call startMusic

    continue:
        ; Continue with the normal flow
        ret
ENDP checkAndResetTimer
    
PROC printTimer
    USES eax, ebx, ecx, edx, esi, edi

    mov ebx, [elapsed_time]
    call setElapsedTime

    cmp ebx, [elapsed_time]
    je skip_print

    call setCursorPosition, 4, 2 ;keep the same cursor position 

    mov eax, [elapsed_time]
    call printDecimal, eax  

    ret
    skip_print:
    ret
ENDP printTimer

; wait for @@framecount frames
proc wait_VBLANK
	ARG @@framecount: word
	USES eax, ecx, edx, ebx, edi, esi
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
    call mouse_uninstall
    call terminateProcess
    
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
    cmp [musicPlaying], 0
    je music_already_stopped
    call stopMusic
    music_already_stopped:
	call setVideoMode, 03h
	mov	ax,04C00h
	int 21h

	ret
ENDP terminateProcess

; function to print a string
PROC printString
    ARG @@string:PTR BYTE
    USES eax, edx

        mov edx, [@@string]
        mov ah, 09h
        int 21h

        ret

ENDP printString

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
; ----------------------------------------------------------------------
; Functions for the grid
; ----------------------------------------------------------------------

; Print grid to screen in text mode
PROC printGrid
    ARG @@bias:BYTE, @@grid:DWORD
    USES eax, ebx, ecx, edx

    ; Initialize pointers and counters
    mov esi, [@@grid]       ; Set ESI to point to the grid array
    mov cx, ROWS            ; Set CX to the number of rows
    mov dx, COLUMNS         ; Set DX to the number of columns

outer_loop_draw:
    push cx                 ; Save outer loop counter
    mov cx, dx              ; Set inner loop counter

inner_loop_draw:
    lodsb                   ; Load byte at [ESI] into AL and increment ESI
    mov bl, [@@bias]
    add esi, ebx
    cmp al, -1              ; Compare AL with -1
    je print_zero           ; Jump if equal
    add al, '0'             ; Convert to ASCII
    jmp print_char          ; Jump to print_char

print_zero:
    mov al, ':'             ; Set AL to ':'

print_char:
    mov ah, 0Eh             ; BIOS teletype function
    int 10h                 ; Call BIOS interrupt to print character
    loop inner_loop_draw    ; Repeat for each column

    ; Print newline
    mov al, 0Dh             ; Carriage return
    int 10h
    mov al, 0Ah             ; Line feed
    int 10h

    pop cx                  ; Restore outer loop counter
    loop outer_loop_draw    ; Repeat for each row

    ; Print newline
    mov al, 0Dh             ; Carriage return
    int 10h
    mov al, 0Ah             ; Line feed
    int 10h

    ret
ENDP printGrid

; Change content of a cell in the grid
PROC updateCell
    ARG @@x:BYTE, @@y:BYTE, @@value:BYTE, @@bias:BYTE, @@grid:DWORD
    USES eax, ebx, ecx, edx, esi, edi

    ; Calculate the offset of the cell in the grid
    mov edi, [@@grid]
    movzx eax, [@@y]
    imul eax, COLUMNS
    movzx ecx, [@@bias]
    imul eax, ecx            ; Size of the entity structure
    movzx ebx, [@@x]
    imul ebx, ecx            ; Size of the entity structure
    add eax, ebx

    ; Set the value of the cell
    add edi, eax
    mov al, [@@value]
    stosb

    ret
ENDP updateCell

; Function to initialize a region with all necessary fields
PROC initializeRegion
    ARG @@regionIndex:BYTE, @@x_min:WORD, @@x_max:WORD, @@y_min:WORD, @@y_max:WORD, @@region_type:BYTE, @@sub_type:BYTE
    USES eax, ebx, ecx, edx, esi, edi

    ; Initialize fields
    movzx eax, [@@regionIndex]
    movzx ebx, [@@x_min]
    call updateRegionCell, eax, REGION_x_min, ebx, 2

    movzx ebx, [@@x_max]
    call updateRegionCell, eax, REGION_x_max, ebx, 2

    movzx ebx, [@@y_min]
    call updateRegionCell, eax, REGION_y_min, ebx, 2

    movzx ebx, [@@y_max]
    call updateRegionCell, eax, REGION_y_max, ebx, 2

    movzx ebx, [@@region_type]
    call updateRegionCell, eax, REGION_region_type, ebx, 1

    movzx ebx, [@@sub_type]
    call updateRegionCell, eax, REGION_sub_type, ebx, 1

    ret
ENDP initializeRegion

; Function to update a cell in a REGION struct
PROC updateRegionCell
    ARG @@regionIndex:BYTE, @@fieldOffset:BYTE, @@value:BYTE, @@size:BYTE
    USES eax, ebx, ecx, edx, esi, edi

    ; Calculate the address of the region field
    mov esi, offset regions      ; Base address of regions array
    movzx eax, [@@regionIndex]   ; Region index
    imul eax, REGION_SIZE        ; Multiply by size of REGION struct
    add esi, eax                 ; Move to the specific REGION struct

    movzx ebx, [@@fieldOffset]   ; Field offset within the REGION struct
    add esi, ebx                 ; Move to the specific field

    ; Store the value at the address
    movzx eax, [@@value]         ; Value to store
    movzx ecx, [@@size]          ; Size of the field (1 for BYTE, 2 for WORD)
    cmp ecx, 1
    je store_byte
    cmp ecx, 2
    je store_word
    jmp end_updateRegionCell     ; Exit if size is invalid

store_byte:
    mov [esi], al
    jmp end_updateRegionCell

store_word:
    mov [esi], ax
    jmp end_updateRegionCell

end_updateRegionCell:
    ret
ENDP updateRegionCell

; Function that displays state of an entity in the grid
PROC printStaticEntityState
    ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, esi

    ; Calculate the offset of the cell in the grid
    mov esi, offset grid
    movzx eax, [@@y]
    imul eax, COLUMNS
    imul eax, ENTITY_SIZE
    movzx ebx, [@@x]
    imul ebx, ENTITY_SIZE
    add eax, ebx
    add esi, eax
    mov ecx, ENTITY_SIZE

get_values_loop_static:
    xor eax, eax
    lodsb
    call printDecimalWithoutNewLine, eax
    loop get_values_loop_static

    ret
ENDP printStaticEntityState

; Function that returns the type of an entity in the grid
PROC getStaticEntityType
    ARG @@x:BYTE, @@y:BYTE RETURNS eax
    USES ebx, ecx, edx, esi

    ; Calculate the offset of the cell in the grid
    movzx eax, [@@x]
    movzx ebx, [@@y]
    call calculateEntityGridOffset, eax, ebx, offset grid
    mov esi, eax
    xor eax, eax

    mov al, [esi]
    cmp al, -1
    je unknown_entity_static
    movzx eax, al
    ret

unknown_entity_static:
    mov eax, 255
    ret
ENDP getStaticEntityType

; Function that initializes a static entity
PROC initializeStaticEntity
    ARG @@x:BYTE, @@y:BYTE, @@type:BYTE
    USES eax, ebx, ecx, edx, esi

    movzx eax, [@@x]
    movzx ebx, [@@y]
    movzx ecx, [@@type]
    call updateCell, eax, ebx, ecx, ENTITY_SIZE, offset grid

    ret
ENDP initializeStaticEntity

; Function to remove static entity from the grid
PROC removeStaticEntity
    ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, esi, edi

    ; Update the type to -1 in the grid
    movzx eax, [@@x]
    movzx ebx, [@@y]
    call updateStaticEntityWithValue, eax, ebx, -1, 0

    ret
ENDP removeStaticEntity

; Function to update static entity variables
PROC updateStaticEntityWithValues
    ARG @@x:BYTE, @@y:BYTE, @@health:BYTE, @@damage:BYTE, @@speed:BYTE, @@direction:BYTE, @@animationFrame:BYTE, @@animationTimer:BYTE, @@spriteIndex:BYTE, @@fireInterval:BYTE, @@fireTimer:BYTE
    USES eax, ebx, ecx, edx, edi, esi

    movzx eax, [@@x]
    movzx ebx, [@@y]
    call calculateEntityGridOffset, eax, ebx, offset grid

    mov edi, eax
    inc edi                     ; Skip the type

    ; Update fields
    mov al, [@@health]
    stosb
    mov al, [@@damage]
    stosb
    mov al, [@@speed]
    stosb

    ; Convert x to pixel position and store the result
    movzx eax, [@@x]
    call convertXtoPixelPosition, eax
    stosb                      ; Store as BYTE

    mov al, [@@y]
    stosb
    mov al, [@@direction]
    stosb
    mov al, [@@animationFrame]
    stosb
    mov al, [@@animationTimer]
    stosb
    mov al, [@@spriteIndex]
    stosb
    mov al, [@@fireInterval]
    stosb
    mov al, [@@fireTimer]
    stosb

    ret
ENDP updateStaticEntityWithValues

; Function to update one value of a static entity
PROC updateStaticEntityWithValue
    ARG @@x:BYTE, @@y:BYTE, @@value:BYTE, @@offset:BYTE
    USES eax, ebx, ecx, edx, edi, esi

    movzx eax, [@@x]
    movzx ebx, [@@y]
    call calculateEntityGridOffset, eax, ebx, offset grid

    mov edi, eax
    movzx eax, [@@offset]
    add edi, eax
    xor eax, eax

    mov al, [@@value]
    stosb

    ret
ENDP updateStaticEntityWithValue

; Function to get the value of a static entity
PROC getValueOfStaticEntity
    ARG @@x:BYTE, @@y:BYTE, @@offset:BYTE RETURNS eax
    USES ebx, ecx, edx, esi, edi

    ; Get the health of the entity
    movzx eax, [@@x]
    movzx ebx, [@@y]
    call calculateEntityGridOffset, eax, ebx, offset grid

    mov edi, eax
    mov cl, [@@offset]
    add edi, ecx               ; Skip to the required value
    mov al, [edi]

    ret
ENDP getValueOfStaticEntity

; Function to print the damage of a static entity
PROC getDamageOfStaticEntity
    ARG @@x:BYTE, @@y:BYTE RETURNS eax
    USES ebx, ecx

    mov bl, [@@x]
    mov cl, [@@y]
    call getValueOfStaticEntity, ebx, ecx, 2 ; Offset 2 for damage

    ret
ENDP getDamageOfStaticEntity

; Function to inflict damage to a static entity and return the health in eax
PROC inflictDamageToStaticEntityFromArray
    ARG @@x:BYTE, @@y:BYTE, @@damage:BYTE RETURNS eax
    USES ebx, ecx, edx, edi, esi

    ; Inflict damage
    movzx eax, [@@x]
    movzx ebx, [@@y]
    call calculateEntityGridOffset, eax, ebx, offset grid

    mov edi, eax
    inc edi                     ; Skip the type
    mov al, [edi]               ; Load the health value
    sub al, [@@damage]
    mov [edi], al               ; Store the updated health

    movzx eax, al               ; Return health

    ret
ENDP inflictDamageToStaticEntityFromArray

; Calculate member grid offset
PROC calculateMemberGridOffset
    ARG @@x:BYTE, @@y:BYTE, @@memberIndex:BYTE RETURNS eax
    USES ebx, ecx, edx

    movzx eax, [@@x]
    movzx ebx, [@@y]
    call calculateEntityGridOffset, eax, ebx, offset grid

    movzx ecx, [@@memberIndex]
    add eax, ecx                ; Add member index to entity offset

    ret
ENDP calculateMemberGridOffset

; Calculate entity grid offset
PROC calculateEntityGridOffset
    ARG @@x:BYTE, @@y:BYTE, @@grid:DWORD RETURNS eax
    USES ebx, ecx, esi

    mov esi, [@@grid]           ; Load grid address into ESI
    movzx eax, [@@y]
    imul eax, COLUMNS
    movzx ebx, [@@x]
    add eax, ebx
    imul eax, ENTITY_SIZE
    add eax, esi                ; Final offset

    ret
ENDP calculateEntityGridOffset

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
            movzx ebx, [@@x]
            add eax, ebx
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
        imul eax, ENTITY_SIZE
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
            call printDecimalWithoutNewLine, eax
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
            call getEntityFromArray, eax
            cmp eax, 255
            jne no_free_position
            jmp found_free_position

        no_free_position:
            call incrementFreeIndex
            jmp find_free_position

        found_free_position:
            mov edi, offset dynamic_entities_array
            movzx eax, [free_index] ; get the current index and multiply it by the size of the entity structure, 8
            imul eax, ENTITY_SIZE
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

; get speed of a dynamic entity
PROC getSpeedOfDynamicEntity
    ARG @@index:BYTE RETURNS eax

        xor eax, eax
        movzx eax, [@@index]
        call getValueOfDynamicEntity, eax, 3 ; 3 is the offset of the speed value

        ret

ENDP getSpeedOfDynamicEntity

; get speed of a dynamic entity based on x and y
PROC getSpeedOfDynamicEntityFromGrid
    ARG @@x:BYTE, @@y:BYTE RETURNS eax
    USES ebx, ecx, esi

        mov esi, offset dynamic_grid
        movzx ebx, [@@y]
        imul ebx, COLUMNS
        add bl, [@@x]
        add esi, ebx
        lodsb

        call getSpeedOfDynamicEntity, eax

        ret

ENDP getSpeedOfDynamicEntityFromGrid

; function to get x of a dynamic entity, the y is not needed because we do not ever change the y of an entity
PROC getXOfDynamicEntity
    ARG @@index:BYTE RETURNS eax

        xor eax, eax
        mov al, [@@index]
        call getValueOfDynamicEntity, eax, 4 ; 3 is the offset of the x value

        ret
ENDP getXOfDynamicEntity

; function to get x from the grid
PROC getXOfDynamicEntityFromGrid
    ARG @@x:BYTE, @@y:BYTE RETURNS al
    USES ebx, ecx

        xor eax, eax
        mov esi, offset dynamic_grid
        movzx ebx, [@@y]
        imul ebx, COLUMNS
        add bl, [@@x]
        add esi, ebx
        lodsb

        call getXOfDynamicEntity, eax

        ret

ENDP getXOfDynamicEntityFromGrid

; function to update x of a dynamic entity
PROC updateXofDynamicEntity
    ARG @@index:BYTE, @@x:BYTE
    USES eax, ebx, ecx, edx, edi, esi

        mov edi, offset dynamic_entities_array
        movzx eax, [@@index]
        imul eax, ENTITY_SIZE
        add edi, eax
        add edi, 4 ; offset of the x value
        xor eax, eax

        mov al, [@@x]
        stosb

        ret

ENDP updateXofDynamicEntity

; increment x of a dynamic entity
PROC incrementXofDynamicEntity
    ARG @@index:BYTE, @@amount:BYTE RETURNS eax ; returns the new x value
    USES ebx, ecx, edx, edi, esi

        xor eax, eax
        mov edi, offset dynamic_entities_array
        movzx eax, [@@index]
        imul eax, ENTITY_SIZE
        add edi, eax
        add edi, 4 ; offset of the x value
        xor eax, eax

        mov al, [edi]
        mov bl, [@@amount]
        add al, bl
        mov [edi], al

        ret

ENDP incrementXofDynamicEntity

; function to get the value of a dynamic entity
PROC getValueOfDynamicEntity
    ARG @@index:BYTE, @@offset:BYTE RETURNS eax
    USES ebx, ecx, edx, esi, edi


        mov edi, offset dynamic_entities_array
        movzx ebx, [@@index]
        imul ebx, ENTITY_SIZE
        add edi, ebx
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
        imul eax, ENTITY_SIZE
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
    ARG @@x:BYTE, @@y:BYTE, @@index:BYTE, @@health:BYTE, @@damage:BYTE, @@speed:BYTE, @@direction:BYTE, @@animationFrame:BYTE, @@animationTimer:BYTE, @@spriteIndex:BYTE
    USES eax, ebx, ecx, edx, edi, esi

        mov edi, offset dynamic_entities_array
        movzx eax, [@@index]
        imul eax, ENTITY_SIZE
        add edi, eax
        inc edi
        xor eax, eax

        mov al, [@@health]
        stosb

        mov al, [@@damage]
        stosb

        mov al, [@@speed]
        stosb

        mov al , 0
        ;call convertXtoPixelPosition, eax ; convert x to pixel position
        stosb

        mov al, 0
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

; function to update the x of a dynamic entity in the grid
PROC incrementXofDynamicEntityFromGrid
    ARG @@x:BYTE, @@y:BYTE, @@amount:BYTE RETURNS eax
    LOCAL @@index:BYTE
    USES ebx, ecx

        mov esi, offset dynamic_grid
        movzx ebx, [@@y]
        imul ebx, COLUMNS
        add bl, [@@x]
        add esi, ebx
        mov al, [esi]
        mov [@@index], al ; save the index temporarily

        movzx ebx, [@@amount]
        call incrementXofDynamicEntity, eax, ebx

        call checkIfXIsOnBoundary, eax ; returns the checked x value in eax, and whether it passed the boundary in ebx

        cmp ebx, 1
        jne no_boundary_passed_increment

        ; if it passed the boundary, subtract 30 from the new x value
        sub eax, 30
        mov cl, [@@index]
        call updateXofDynamicEntity, ecx, eax

        mov eax, 1 ; it passed the boundary

        ret

    no_boundary_passed_increment:
        mov eax, 0 ; it did not pass the boundary

        ret

ENDP incrementXofDynamicEntityFromGrid

; function to remove an entity from the dynamic_grid and subsequently from the dynamic_entities_array
PROC removeDynamicEntity
    ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, edi, esi

        ; first get the index of the entity in the dynamic_entities_array
        ; then set the type of the entity to -1 in the dynamic_grid
        ; then set the type of the entity to -1 in the dynamic_entities_array

        movzx eax, [@@y]
        imul eax, COLUMNS
        movzx ebx, [@@x]
        add eax, ebx
        mov esi, offset dynamic_grid
        add esi, eax
        lodsb
        
        xor edi, edi
        mov edi, offset dynamic_entities_array
        imul eax, ENTITY_SIZE
        add edi, eax
        xor eax, eax
        mov al, -1
        movzx eax, al
        stosb

        movzx eax, [@@y]
        imul eax, COLUMNS
        movzx ebx, [@@x]
        add eax, ebx
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
    imul eax, ENTITY_SIZE
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
        movzx ebx, [@@x1]
        add eax, ebx
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
        movzx ebx, [@@x2]
        add eax, ebx
        
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

; function that clears all registers
PROC clearRegisters

        xor eax, eax
        xor ebx, ebx
        xor ecx, ecx
        xor edx, edx
        xor edi, edi
        xor esi, esi

        ret
ENDP clearRegisters

; function that moves an entity in the positive x direction only once
PROC moveEntityRight
    ARG @@x:BYTE, @@y:BYTE, @@bias:BYTE, @@grid:DWORD
    USES eax, ebx, ecx, edx, edi, esi
    
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
    USES eax, ebx, ecx, edx, edi, esi
    
    mov al, [@@x]
    mov bl, [@@y]
    movzx edi, [@@bias]
    mov esi, [@@grid]
    call moveEntityDirection, eax, ebx, 1, 0, 1, edi, esi

    ret

ENDP moveEntityLeft

; Function to check if a position is free to spawn an entity
PROC isPositionFree
    ARG @@x:BYTE, @@y:BYTE RETURNS eax
    USES ebx, ecx, edx, esi

    ; Check the dynamic grid
    movzx eax, [@@x]
    movzx ebx, [@@y]
    call getEntityType, eax, ebx, offset dynamic_grid
    cmp al, -1
    jne isPositionFree_position_not_free

    ; Check the static grid
    movzx eax, [@@x]
    movzx ebx, [@@y]
    call getStaticEntityType, eax, ebx
    cmp al, -1
    jne isPositionFree_position_not_free

    ; Position is free
    mov eax, 1
    ret

isPositionFree_position_not_free:
    ; Position is not free
    mov eax, 0
    ret

ENDP isPositionFree

; --------------------------------------------------------------------------------------------------------------------------------------

; Game logic

; --------------------------------------------------------------------------------------------------------------------------------------

; get entity type


; get entity types (both mainType and subType)
PROC getEntityTypes
    ARG @@raw:BYTE RETURNS eax, ebx
    USES ecx, edx
        ; function to get both mainType and subType of an entity
        ; type consists of two digits, first digit is type, which discriminates between zombies, plants and so on
        ; the second digit discriminates between different types of the same entity, for example, different types of zombies
        ;
        ; return both the first digit (mainType) and the second digit (subType) of the type
        ; get the result by dividing the type by 10, the result is the mainType, the remainder is the subType
        xor eax, eax
        xor ebx, ebx
        xor edx, edx
        mov al, [@@raw]

        cmp al, -1
        je unknown_entity_get_types
        cmp al, 255
        je unknown_entity_get_types
        
        mov ecx, 10
        div ecx ; divide al by cl, result in al (mainType), remainder in ah (subType)
        movzx eax, al ; mainType in eax
        mov ebx, edx ; subType in ebx

        ret
    unknown_entity_get_types:
        mov eax, 255
        mov ebx, 255

        ret

ENDP getEntityTypes

; get entity mainType
PROC getMainType
    ARG @@raw:BYTE RETURNS eax
    USES ebx

        movzx eax, [@@raw]
        call getEntityTypes, eax

        ret

ENDP getMainType

; get entity subType
PROC getSubType
    ARG @@raw:BYTE RETURNS eax
    USES ebx
        
        movzx eax, [@@raw]
        call getEntityTypes, eax
        mov eax, ebx ; move subType (in ebx) to eax 

        ret
ENDP getSubType

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
            movzx ebx, [@@x]
            add eax, ebx
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
                mov eax, [player_coins]
                add eax, [dead_zombie_reward]
                mov [player_coins], eax

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

PROC decrementFireTimer
    ARG @@x:BYTE, @@y:BYTE RETURNS al
    USES ebx, ecx, edi
    movzx eax, [@@x]
    movzx ebx, [@@y]
    call getValueOfStaticEntity, eax, ebx, 11
    dec al

    movzx ecx, [@@x]
    movzx ebx, [@@y]
    call updateStaticEntityWithValue, ecx, ebx, eax, 11
    
    ret
ENDP decrementFireTimer

PROC resetFireTimer
    ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edi

    movzx eax, [@@x]
    movzx ebx, [@@y]
    call updateStaticEntityWithValue, eax, ebx, FIRETIMER, 11

    ret
ENDP resetFireTimer

; **MOVEMENT**
; has to go from right to left, top to bottom otherwise the entities will move in the wrong order

; function to handle update of X of dynamic entities
PROC handleXupdate
    ARG @@x:BYTE, @@y:BYTE, @@amount:BYTE RETURNS eax
    USES ebx, ecx

    ; increment x of the entity
    ; check if it is on the bounds with checkIfXIsOnBoundary, returns 1 if the entity passed the boundary

    xor eax, eax
    mov al, [@@x]
    mov bl, [@@y]
    mov cl, [@@amount]
    call incrementXofDynamicEntityFromGrid, eax, ebx, ecx ; returns the new x value in eax

    ret

ENDP handleXupdate

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
            call getMainType, eax 
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

            mov al, [@@x]
            mov bl, [@@y]
            push eax
            call getEntityType, eax, ebx, offset dynamic_grid
            cmp al, 255
            jne checker
            pop eax
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
            cmp eax, 0
            je move_projectile_right
            cmp eax, 2
            je inflict_dmg
            ret

        move_projectile_right:
            ;mov al, [@@x]

            ;call getSpeedOfDynamicEntityFromGrid, eax, ebx
            ;mov ecx, eax
            ;movzx eax, [@@x]
            ;movzx ebx, [@@y]
            ;call handleXupdate, eax, ebx, ecx
            ;cmp eax, 1 ; check if the projectile passed the boundary
            je move_projectile_to_the_right
            ret

        move_projectile_to_the_right:
            mov al, [@@x]
            call moveEntityRight, eax, ebx, 1, offset dynamic_grid
            ret

        inflict_dmg:
            movzx eax, [@@x]
            call getDamageOfDynamicEntityFromGrid, eax, ebx
            mov ecx, eax
            movzx eax, [@@x]
            inc eax
            call inflictDamageToDynamicEntityFromGrid, eax, ebx, ecx ; TODO: damage should be a variable
            

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
            mov eax, 0
            pop eax
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
            call getSpeedOfDynamicEntityFromGrid, eax, ebx
            mov ecx, eax
            movzx eax, [@@x]
            call handleXupdate, eax, ebx, ecx
            cmp eax, 1 ; check if the zombie passed the boundary
            je move_entity_to_the_left
            mov eax, 0
            ret
        
        move_entity_to_the_left:
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

            mov eax, [player_hearts]
            dec eax
            mov [player_hearts], eax
            cmp eax, 0
            je show_game_over

            mov eax, 0
            ret
        show_game_over:
            call showGameOverScreen
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
            call getMainType, eax ; get rid of the second digit
            movzx ecx, al ; type of first entity in cl
            mov al, [@@x2]
            mov bl, [@@y2]
            call getEntityType, eax, ebx, offset dynamic_grid
            call getMainType, eax
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
            call getMainType, eax ; get rid of the second digit
            movzx ecx, al ; type of first entity in cl
            mov al, [@@x2]
            mov bl, [@@y2]
            call getStaticEntityType, eax, ebx
            call getMainType, eax
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
        
        cmp al, 1
        je invalid_entity_spawn_projectiles
        cmp al, 2
        je invalid_entity_spawn_projectiles

        ; Decrement fireTimer
        movzx eax, [@@x]
        movzx ebx, [@@y]
        call decrementFireTimer, eax, ebx
        cmp al, 0
        jge invalid_entity_spawn_projectiles

        ; if fireTimer equals 0, spawn projectile
        movzx eax, [@@x]
        movzx ebx, [@@y]
        call spawnProjectile, eax, ebx

        ; Reset fireTimer
        movzx eax, [@@x]
        movzx ebx, [@@y]
        call resetFireTimer, eax, ebx

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
            call getMainType, eax
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
            mov bl, [@@x]
            mov cl, [@@y]
            call updateDynamicEntityWithValues, ebx, ecx, eax, 20, edx, 1, 0, 0, 0, 0

            ret

ENDP spawnProjectile

; function to spawn zombie at a given position
PROC spawnDefaultZombie
    ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, edi, esi

        ; spawn a zombie at the given position with default values

        movzx eax, [@@x]
        movzx ebx, [@@y]
        call initializeDynamicEntity, eax, ebx, 10
        ; returns the index of the entity in eax
        mov bl, [@@x]
        mov cl, [@@y]
        call updateDynamicEntityWithValues, ebx, ecx, eax, 8, 2, 1, 0, 0, 0, 0, 20, 20

        ret

ENDP spawnDefaultZombie     

; function to spawn zombie at a given position
PROC spawnStrongZombie
    ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, edi, esi
        ; Check if the position is free
        movzx eax, [@@x]
        movzx ebx, [@@y]
        call isPositionFree, eax, ebx
        cmp eax, 0
        je spawnDefaultZombie_position_not_free
        ; spawn a zombie at the given position with default values
        movzx eax, [@@x]
        movzx ebx, [@@y]
        call initializeDynamicEntity, eax, ebx, 11
        ; returns the index of the entity in eax
        mov bl, [@@x]
        mov cl, [@@y]
        call updateDynamicEntityWithValues, ebx, ecx, eax, 20, 3, 1, 0, 0, 0, 0, 20, 20

        ret

ENDP spawnStrongZombie 

; function to spawn zombie at a given position
PROC spawnLeapZombie
    ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, edi, esi

        ; spawn a zombie at the given position with default values
        movzx eax, [@@x]
        movzx ebx, [@@y]
        call initializeDynamicEntity, eax, ebx, 12
        ; returns the index of the entity in eax
        mov bl, [@@x]
        mov cl, [@@y]
        call updateDynamicEntityWithValues, ebx, ecx, eax, 35, 4, 1, 0, 0, 0, 0, 20, 20

        ret
    spawnDefaultZombie_position_not_free:
        ret

ENDP spawnLeapZombie 

; function to spawn plant at a given position
PROC spawnDefaultPlant
    ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, edi, esi

        ; spawn a plant at the given position with default values

        movzx eax, [@@x]
        movzx ebx, [@@y]
        ; call printMouseCoordinates, eax, ebx

        call initializeStaticEntity, eax, ebx, 0
        movzx ecx, [default_plant_health]
        call updateStaticEntityWithValues, eax, ebx, ecx, 3, 1, 0, 0, FIREINTERVAL, FIRETIMER
        

        ret

ENDP spawnDefaultPlant

; function to spawn potato at a given position
PROC spawnPotato
ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, edi, esi

        ; spawn a plant at the given position with default values

        movzx eax, [@@x]
        movzx ebx, [@@y]
        call initializeStaticEntity, eax, ebx, 1
        movzx ecx, [potato_health]
        call updateStaticEntityWithValues, eax, ebx, ecx, 0, 0, 0, 0, 0, 0 ; a potato does not have damage, means that it can not spawn a projectile

        ret
ENDP spawnPotato

; function to spawn potato at a given position
PROC spawnBiggerPotato
ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, edi, esi

        ; spawn a plant at the given position with default values

        movzx eax, [@@x]
        movzx ebx, [@@y]
        call initializeStaticEntity, eax, ebx, 2
        movzx ecx, [bigger_potato_health]
        call updateStaticEntityWithValues, eax, ebx, ecx, 0, 0, 0, 0, 0, 0 ; a potato does not have damage, means that it can not spawn a projectile

        ret
ENDP spawnBiggerPotato

PROC spawnBiggerPlant
    ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, edi, esi

        ; spawn a plant at the given position with default values

        movzx eax, [@@x]
        movzx ebx, [@@y]
        call initializeStaticEntity, eax, ebx, 3
        movzx ecx, [bigger_plant_health]
        call updateStaticEntityWithValues, eax, ebx, ecx, 3, 1, 0, 0, FIREINTERVAL, FIRETIMER

        ret

ENDP spawnBiggerPlant

PROC spawnBiggestPlant
    ARG @@x:BYTE, @@y:BYTE
    USES eax, ebx, ecx, edx, edi, esi

        ; spawn a plant at the given position with default values

        movzx eax, [@@x]
        movzx ebx, [@@y]
        call initializeStaticEntity, eax, ebx, 4
        movzx ecx, [biggest_plant_health]
        call updateStaticEntityWithValues, eax, ebx, ecx, 3, 1, 0, 0, FIREINTERVAL, FIRETIMER

        ret

ENDP spawnBiggestPlant

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
            call handleMovement, ecx, ebx ; gets x, y arguments
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
            jmp inner_loop_update_game_state ; continue iterating if not at the end of a row

        spawn_the_projectile_on_position:
            movzx ebx, [@@currentY]
            call handleProjectileSpawning, ecx, ebx
            jmp after_checking_local

        set_spawn_projectile:
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
        ; if we are at the last column, skip the drawing, since we do not want to draw the entities that are out of the screen
        cmp eax, 9 ; 9 is the last column, this one is not visible
        je after_draw_dynamic_entity
        imul eax, 30
        add eax, 50
        push ecx
        mov ecx, eax
        movzx eax, [@@type]
        call getEntityFromArray, eax
        push eax
        movzx eax, [@@type]
        call getXOfDynamicEntity, eax
        sub ecx, eax
        pop eax
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
        cmp al, -1
        je after_draw_entity
        cmp al, 255
        jne draw_plant_entity
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
        
        call drawEntity, eax, ebx, ecx
        pop ecx
        jmp after_draw_entity
    
    after_draw_entity:
        loop inner_loop_draw_plants
        
        pop ecx
        loop outer_loop_draw_plants

        ret
ENDP drawStaticEntitiesOnGrid

; function to add x offset to the x position of the entity
PROC addXoffset
    ARG @@x:BYTE, @@y:BYTE RETURNS eax
    USES ebx

    xor eax, eax
    ; get the x of the entity
    mov al, [@@x]
    mov bl, [@@y]
    call getXOfDynamicEntityFromGrid, eax, ebx ; returns the x of the entity in eax

    ; add the offset to the x
    mov bl, al
    mov al, [@@x]
    add al, bl
    movzx eax, al

    ret

ENDP addXoffset

; function to draw an entity, given a type
PROC drawEntity
    ARG @@x0:word, @@y0:word, @@type:byte
    USES eax, ebx, ecx, edx, edi

        ; check the type of the entity
        ; draw the entity based on the type

        movzx eax, [@@type] ; TODO make switch case
        movzx ebx, [@@x0]
        movzx ecx, [@@y0]
        cmp al, 0
        je draw_plant
        cmp al, 1
        je draw_potato
        cmp al, 2
        je draw_bigger_potato
        cmp al, 3
        je draw_bigger_plant
        cmp al, 4
        je draw_biggest_plant
        cmp al, 10
        je draw_zombie
        cmp al, 11
        je draw_strong_zombie
        cmp al, 12
        je draw_leap_zombie
        cmp al, 20
        je draw_projectile
        ret
    
    draw_plant:
        call drawSprite, offset sprite1, VMEMADR, ebx, ecx
        ret

    draw_zombie:
        call drawSprite, offset sprite3, VMEMADR, ebx, ecx
        ret

    draw_strong_zombie:
        call drawSprite, offset sprite4, VMEMADR, ebx, ecx
        ret

    draw_leap_zombie:
        call drawSprite, offset sprite5, VMEMADR, ebx, ecx
        ret
    
    draw_projectile:
        call drawProjectile, ebx, ecx
        ;call drawSprite, offset sprite2, VMEMADR, ebx, ecx
        ret

    draw_potato:
        call drawSprite, offset sprite6, VMEMADR, ebx, ecx
        ret

    draw_bigger_potato:
        call drawSprite, offset sprite7, VMEMADR, ebx, ecx
        ret

    draw_bigger_plant:
        call drawSprite, offset sprite8, VMEMADR, ebx, ecx
        ret

    draw_biggest_plant:
        call drawSprite, offset sprite9, VMEMADR, ebx, ecx
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
    add eax, 20
    mov bx, [@@y0]
    add ebx, 14
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

; function to render the game state
PROC renderFrame
    USES eax, ebx, ecx, edx, edi, esi

    call wait_VBLANK, 1 ; wait for the next frame
    call fillBackgroundFaster, 95 ; fill the screen with white
    
    call drawStaticEntitiesOnGrid, 11, offset grid ; draw the plants
    call drawDynamicEntitiesOnGrid, 0, offset dynamic_grid ; draw the zombies and projectiles 
    call drawBackground ; draw the grid
    call drawColoredRectangle, 0, 0, 50, 200, 0 ; draw the left side of the screen
    call drawShopInterface
    call displayCoins
    call displayHearts

    call ShowCursor ; show the mouse cursor on the screen

    call displayLevelName
    call displayWaveNumber

    ret

ENDP renderFrame

; ----------------------------------------------------------------------
; MOUSE

PROC mouse_uninstall
    USES    eax, ecx, edx

    mov     eax, 0ch
    mov     ecx, 0
    mov     edx, 0
    int     33h

    ret
ENDP mouse_uninstall

PROC mouse_present
    USES    ebx

    mov     eax, 0
    int     33h

    and     eax, 1
    ret
ENDP mouse_present

PROC mouse_internal_handler NOLANGUAGE
    push    ds
    push    es
    push    ax

    mov     ax, [cs:theDS]
    mov     ds, ax
    mov     es, ax

    pop     ax

    call    [custom_mouse_handler]
    
    pop     es
    pop     ds
    
    retf

    ; Internal variable to keep track of D
    theDS   dw  ?
ENDP mouse_internal_handler

PROC mouse_install
    ARG     @@custom_handler
    USES    eax, ecx, edx, es

    call    mouse_present
    cmp     eax, 1
    jne     @@no_mouse

    mov     eax, [@@custom_handler]
    mov     [custom_mouse_handler], eax

    push    ds
    mov     ax, cs
    mov     ds, ax
    ASSUME  ds:_TEXT
    mov     [theDS], ax
    ASSUME  ds:FLAT
    pop     ds

    mov     eax, 0ch
    mov     ecx, 255
    push    cs
    pop     es
    mov     edx, offset mouse_internal_handler
    int     33h

@@no_mouse:
    ret
ENDP mouse_install

PROC ShowCursor
    USES eax
    
    mov ax, 1
    int 33h

    ret
ENDP ShowCursor

;drawCrosshair currently not used
PROC drawCrosshair
    ARG     @@x:WORD, @@y:WORD
    USES    eax, ebx, edi

    ; Set up video memory address
    mov     edi, VMEMADR

    ; Calculate the top-left corner of the rectangle
    movzx   eax, [@@x]
    ; sub     eax, 5          ; Offset for centering horizontally
    movzx   ebx, [@@y]
    ; sub     ebx, 5          ; Offset for centering vertically

    ; Draw the rectangle
    call    drawColoredRectangle, eax, ebx, 10, 10, 15 ; 10x10 rectangle with color 15 (white)

    ret
ENDP drawCrosshair

PROC mouseHandler
    USES    eax, ebx, ecx, edx
	
	and bl, 3			; check for two mouse buttons (2 low end bits)
	jz @@skipit			; only execute if a mousebutton is pressed

    movzx eax, dx		; get moused height
	mov edx, SCRWIDTH
	mul edx				; obtain vertical offset in eax
	sar cx, 1			; horizontal cursor position is doubled in input 
	add ax, cx			; add horizontal offset
	add eax, VMEMADR	; eax now contains pixel address mouse is pointing to
	mov [eax], bl		; change color

	@@skipit:
    ret
ENDP mouseHandler

PROC handleMouseClick
    USES eax, ebx, ecx, edx
    xor ecx, ecx
    xor edx, edx
    ; Check the status of the mouse buttons
    mov ax, 3
    int 33h

    sar cx, 1			; horizontal cursor position is doubled in input 
    mov [mouseX], ecx
    mov [mouseY], edx
    
        ; The status of the buttons is in bx
    test bx, 1       ; Left mous button clicked? 
    jz no_click
    ; call printMouseCoordinates, [mouseX], [mouseY]

    call convertScreenCoordsToGridCoords, ecx, edx ;returns 255 if screenscoords out of bound
    
    cmp eax, 255
    jne call_SpawnSolver
    call RegionSolver, ecx, edx
    ret

call_SpawnSolver:
    movzx ecx, [selected_shop]
    
    ; call SpawnSolver, eax, ebx
    call spawnEntityType, eax, ebx, ecx
    ret

no_click:
    ret
ENDP handleMouseClick

PROC printMouseCoordinates
    ARG @@x:WORD, @@y:WORD
    USES eax, ebx, ecx, edx

    ; Set cursor position 
    call setCursorPosition, 5, 0

    ; Print 'X:'
    call printChar, 88 ; 'ASCII for X'
    call printChar, 58 ; 'ASCII for :'
    ; Print the X coordinate
    movzx eax, [@@x]
    call printDecimalWithoutNewLine, eax

    ; Set cursor position 
    call setCursorPosition, 8, 0

    ; Print 'Y:'
    call printChar, 89 ; 'ASCII for X'
    call printChar, 58 ; 'ASCII for :'
    ; Print the Y coordinate
    movzx eax, [@@y]
    call printDecimalWithoutNewLine, eax

    ret
ENDP printMouseCoordinates

;set mouseX and mouseY to currect mouse position (currently not in use)
PROC getMouseCoordinates 
    USES eax, ebx, ecx, edx

    mov ax, 3
    int 33h

    sar cx, 1			; horizontal cursor position is doubled in input 

    mov [mouseX], ecx
    mov [mouseY], edx
    call printMouseCoordinates, ecx, edx

    ret
ENDP getMouseCoordinates

;limiting the mouse position window (for later use)
PROC setMouseVerticalLimit
    ARG @@MIN:WORD, @@MAX:WORD
    USES eax, ebx, ecx, edx

    mov ax, 8
    mov cx, [@@MIN]
    mov dx, [@@MAX]

    int 33h

    ret
ENDP setMouseVerticalLimit

PROC setMouseHorizontalLimit
    ARG @@MIN:WORD, @@MAX:WORD
    USES eax, ebx, ecx, edx

    mov ax, 7
    mov cx, [@@MIN]
    mov dx, [@@MAX]

    int 33h

    ret
ENDP setMouseHorizontalLimit

PROC setMouseLimits
    ARG @@XMIN:WORD, @@XMAX:WORD, @@YMIN:WORD, @@YMAX:WORD
    USES eax, ebx, ecx, edx

    call setMouseHorizontalLimit, [@@XMIN], [@@XMAX]
    call setMouseVerticalLimit, [@@YMIN], [@@YMAX]

    int 33h

    ret
ENDP setMouseLimits

; --------------------------------------------------------------------------------------------------------------------------------------
; SPRITE DRAWING


PROC ReadFile
	ARG	 @@filepathptr: dword,@@dataptr: dword,@@noofbytes: dword 
	USES eax, ebx, ecx, edx, esi, edi
	
	; open file, get filehandle in AX
	mov al, 0 ; read only
	mov edx, [@@filepathptr]
	mov ah, 3dh
	int 21h
	
	mov  edx, offset openErrorMsg
	jc @@print_error ; carry flag is set if error occurs

	; read file data 
	mov bx, ax ; move filehandle to bx
	mov ecx, [@@noofbytes]
	mov edx, [@@dataptr]
	mov ah, 3fh
	int 21h

	mov  edx, offset readErrorMsg
	jc @@print_error
	
	; close file
	mov ah, 3Eh
	int 21h
	
	mov  edx, offset closeErrorMsg
	jc @@print_error
	
	ret

@@print_error:
	call setVideoMode, 03h
	mov  ah, 09h
	int  21h
	
	mov	ah,00h
	int	16h
	call terminateProcess	
ENDP ReadFile

PROC drawSprite
    ARG @@spritePtr :dword, \
    @@dstPtr :dword, \
    @@x:dword, \
    @@y:dword
    LOCAL @@w:dword, @@h:dword
    USES eax , ebx , ecx , edx , esi , edi
    mov esi , [ @@spritePtr ]
    xor eax , eax
    lodsd ; read width in EAX
    mov [@@w] , eax
    lodsd ; read heigh in EAX
    mov [@@h] , eax
    mov edi , [ @@dstPtr ]
    mov eax , [@@y]
    mov ebx , SCRWIDTH
    mul ebx
    add edi , eax
    add edi , [@@x] ; EDI po in ts to f i r s t p i x e l
    mov ecx , [@@h]
    @@drawLine :
    push ecx
    mov ecx , [@@w] ; need to copy a l in e o f the s p r i t e
    rep movsb ; copy from e s i to ed i
    add edi , SCRWIDTH
    sub edi , [@@w] ; ed i now po in ts to the next l in e in d s t
    pop ecx
    dec ecx
    jnz @@drawLine
    ret
ENDP drawSprite

MACRO waitForKeystroke
	mov	ah,00h
	int	16h
ENDM waitForKeystroke



; --------------------------------------------------------------------------------------------------------------------------------------

; AUDIO

; --------------------------------------------------------------------------------------------------------------------------------------


PROC reset_dsp
	mov dx, SB_BASE
	add dl, 6
	
	mov al, 1
	out dx, al
	sub al, al
@@delay:
	dec al
	jnz @@delay
	out dx, al
	
	sub cx, cx
@@empty:
	mov dx, SB_BASE
	add dl, 0eh
	
	in al, dx
	or al, al
	jns @@next_attempt
	
	sub dl, 4
	in al, dx
	cmp al, 0aah
	je @@reset_ok
	
@@next_attempt:	
	loop @@empty
	
@@reset_ok:
	ret
ENDP reset_dsp

; bl = data
PROC write_dsp
	mov dx, SB_BASE
	add dl, 0ch
@@busy:
	in al, dx
	or al, al
	js @@busy
	
	mov al, bl
	out dx, al
	ret
ENDP write_dsp
	
; out: al 		
PROC read_dsp
	mov dx, SB_BASE
	add dl, 0eh
@@busy:
	in al, dx
	or al, al
	jns @@busy
	
	sub dl, 4
	in al, dx
	ret
ENDP read_dsp
					
PROC turn_speaker_on
	mov bl, 0d1h
	call write_dsp
	ret
ENDP turn_speaker_on
			
PROC turn_speaker_off
	mov bl, 0d3h
	call write_dsp
	ret
ENDP turn_speaker_off
			
PROC disable_irq_7
	in al, 21h
	or al, 10000000b
	out 21h, al
	ret
ENDP disable_irq_7
			
PROC enable_irq_7
	in al, 21h
	and al, 01111111b
	out 21h, al
	ret
ENDP enable_irq_7
			
PROC irq_7_handler NOLANGUAGE
	pushad
	bt [readbusy], 0	; verify if file is being read at the moment
	jnc @@goahead		; delay sound stream reading if busy? otherwise go ahead.
	mov [readfail], 1	; signal failure
	jmp @@skipcopy
@@goahead:
	call readMusicPiece
@@skipcopy:
	
	; SB 8-bit ack
	mov dx, SB_BASE + 0eh
	in al, dx
	
	; EOI
	mov al, 20h
	out 20h, al
	
	popad
	iret
ENDP irq_7_handler
			
PROC install_isr
	mov ax, cs
	mov ds, ax   	; load data segment with code segment (the one we are in now)
	mov ah, 25h 	; Set Interrupt Vector Command
	mov al, INT_NUMBER ; Interrupt to replace
	mov edx, offset irq_7_handler
	int 21h
	ret
ENDP install_isr
			
PROC program_dma
	mov dx, 0ah ; write single mask register
	mov al, 05h ; disable DMA channel 1
	out dx, al
	
	mov dx, 0ch ; clear byte pointer flip flop
	mov al, 0 ; any value
	out dx, al 
	
	mov dx, 0bh ; write mode register
	mov al, 59h ; auto-init playback
	out dx, al
	
	mov dx, 03h ; channel 1 count
	mov ax, (SND_BUFF_SIZE - 1)
	out dx, al ; low byte
	mov ax, (SND_BUFF_SIZE - 1) / 256
	out dx, al ; high byte
	

	mov dx, 02h ; channel 1 address
	mov eax, [buffer_start]
	out dx, al ; low byte
	mov al, ah
	out dx, al ; high byte
	
	mov dx, 83h ; page register for 8-bit DMA channel 1
	shr eax, 16
	out dx, al
	
	mov dx, 0ah ; write single mask register
	mov al, 01h ; enable DMA channel 1
	out dx, al
	
	ret
ENDP program_dma

PROC set_sampling_rate
	mov bl, 40h ; time constant
	call write_dsp
	mov bl, 0D3h ; ~22KHz
	call write_dsp
	ret
ENDP set_sampling_rate
			
PROC start_playback
	mov bl, 48h ; set block size for 8-bit auto-init mode
	call write_dsp
	mov bx, (SND_BUFF_SIZE / 2 - 1) ; low byte
	call write_dsp
	mov bx, (SND_BUFF_SIZE / 2 - 1) / 256 ; high byte
	call write_dsp
	
	mov bl, 1ch ; start auto-init 8-bit DMA transfer
	call write_dsp

	ret
ENDP start_playback

PROC exit_auto_init
	mov bl, 0dah
	call write_dsp
	ret
ENDP exit_auto_init

PROC calculate_sound_buffer_page_offset
	mov eax, offset sound_buffer
	cmp ax, 65536 - SND_BUFF_SIZE
	jbe @@size_ok
	xor ax, ax
	dec ax
	inc eax
@@size_ok:
	mov [buffer_start], eax
	ret
ENDP calculate_sound_buffer_page_offset


; opens file with pointer to filename, returns file handle in ax
PROC openFile
	ARG	@@filename:dword RETURNS ax
	USES ebx, ecx, edx
	mov al, 0 ; read only
	mov edx, [@@filename]
	mov ah, 3dh
	int 21h
	
	jnc @@no_error ; carry flag is set if error occurs

	call setVideoMode, 03h
	mov  ah, 09h
	mov  edx, offset openErrorMsg
	int  21h
	
	mov	ah, 00h
	int	16h
	call terminateProcess
	
@@no_error:
	ret
ENDP openFile

; reads chunk to buffer
PROC readChunk
	ARG	@@destptr:dword, @@buffersize:dword, @@handle:word
	USES eax, ebx, ecx, edx
	movzx ebx, [@@handle]
	mov ecx, [@@buffersize]
	mov edx, [@@destptr]
	mov ah, 3fh
	int 21h
	
	jnc @@no_error ; carry flag is set if error occurs

	call setVideoMode, 03h
	mov  ah, 09h
	mov  edx, offset readErrorMsg
	int  21h
	
	mov	ah,00h
	int	16h
	call terminateProcess
	
@@no_error:
	ret
ENDP readChunk

; closes file
PROC closeFile
	USES eax, ebx, ecx, edx
	ARG	@@handle:word
	movzx ebx, [@@handle]
	mov ah, 3Eh
	int 21h
	
	jnc @@no_error ; carry flag is set if error occurs

	call setVideoMode, 03h
	mov  ah, 09h
	mov  edx, offset closeErrorMsg
	int  21h
	
	mov	ah,00h
	int	16h
	call terminateProcess
	
@@no_error:
	ret
ENDP closeFile

PROC readMusicPiece
	USES edi
	mov edi, [buffer_start]
	neg [buffhalf]
	jl @@firsthalf
	add edi, SND_BUFF_SIZE/2
@@firsthalf:
	call readChunk, edi, SND_BUFF_SIZE/2, [sndhandle]
	ret
ENDP readMusicPiece

; -------------------------------------------------------------------

PROC startMusic
        pushad
        call openFile, offset sound_file
        mov [sndhandle], ax
        mov [musicPlaying], 1

        call reset_dsp	
        call turn_speaker_on
        call install_isr
        
        call enable_irq_7
        call calculate_sound_buffer_page_offset
        call program_dma
        call set_sampling_rate
        
        call readMusicPiece
        call readMusicPiece
        call start_playback
        popad

        ret
ENDP startMusic

PROC stopMusic
	pushad
	call exit_auto_init
	call disable_irq_7
	call turn_speaker_off
	call closeFile, [sndhandle]
    mov [musicPlaying], 0
	popad
	ret
ENDP stopMusic

; --------------------------------------------------------------------------------------------------------------------------------------

; LEVEL processing

; --------------------------------------------------------------------------------------------------------------------------------------


; function to display the level name
PROC displayLevelName
    USES eax, ebx, ecx, edx

    ; get the current level name
    mov ebx, [current_level]
    mov eax, [ebx + LEVEL.level_name]


    ; Set cursor position 
    call setCursorPosition, 0, 0

    ; Print the level name
    call printString, eax

    ret

ENDP displayLevelName

; function to display the wave number
PROC displayWaveNumber
    USES eax, ebx, ecx, edx

    call setCursorPosition, 2, 2

    ; get the current wave number
    mov ebx, [current_level]
    movzx eax, [current_wave]
    inc eax
    movzx ecx, [ebx + LEVEL.waves_count]
    call printDecimalWithoutNewLine, eax
    call setCursorPosition, 2, 3
    call printString, offset msg_wave_interval
    call setCursorPosition, 2, 4

    ; print the total number of waves
    call printDecimalWithoutNewLine, ecx

    ret

ENDP displayWaveNumber

; function to increment the spawn counter
PROC incrementSpawnCounter
    ARG RETURNS eax
    USES ebx, ecx, edx, edi, esi

        ; increment the spawn counter
        ; if it is equal to SPAWN_INTERVAL, reset the counter to 0 and return 1, otherwise return 0

        mov al, [spawn_counter]
        inc al
        cmp al, SPAWN_INTERVAL
        jne not_reset
        mov al, 0
        mov [spawn_counter], al
        mov eax, 1
        ret

    not_reset:
        mov [spawn_counter], al
        mov eax, 0
        ret

ENDP incrementSpawnCounter

; function to increment entity counter
PROC incrementEntityCounter
    ARG RETURNS eax
    USES ebx, ecx, edx, edi, esi

        ; increment the entity counter
        ; if it is equal to the number of entities in the current wave, reset the counter to 0 and return 1, otherwise return 0

        mov al, [current_entity]
        inc al

        cmp al, [wave_length]
        jne not_reset_entity_counter
        mov al, 0
        mov [current_entity], al
        mov eax, 1
        ret

    not_reset_entity_counter:
        mov [current_entity], al
        mov eax, 0
        ret

ENDP incrementEntityCounter

; function to increment the wave counter
PROC incrementWaveCounter
    ARG RETURNS eax
    USES ebx, ecx, edx, edi, esi

        ; increment the wave counter
        ; if it is equal to wave_length, reset the counter to 0 and return 1, otherwise return 0

        mov al, [current_wave]
        inc al
        mov ebx, [current_level]
        movzx ecx, [ebx + LEVEL.waves_count]
        cmp al, cl
        jne not_reset_wave_counter
        mov al, 0
        mov [current_wave], al
        mov eax, 1
        ret

    not_reset_wave_counter:
        mov [current_wave], al
        mov eax, 0
        ret

ENDP incrementWaveCounter

; function to increment the level counter
PROC incrementLevelCounter
    ARG RETURNS eax
    USES ebx, ecx, edx, edi, esi

        ; increment the level counter
        ; check if it is the last level, if it is, return 1
        ; if it is not the last level:
        ; - update the current level pointer to the next level

        mov al, [current_level_index]
        inc al
        cmp al, LEVELS_COUNT
        je last_level_exit
        mov [current_level_index], al
        movzx eax, al
        mov ebx, offset level_array
        mov ecx, [ebx + eax * 4]
        mov [current_level], ecx
        mov eax, 0
        ret

    last_level_exit:
        mov eax, 1
        ret

ENDP incrementLevelCounter

; function to find a free spot in the grid
; function to spawn entity at a given position given the type of the entity
PROC spawnEntityType
    ARG @@x:BYTE, @@y:BYTE, @@type:BYTE RETURNS eax
    USES ebx, ecx, edx, edi, esi
        
        xor eax, eax
        ; check if the position is valid
        movzx eax, [@@x]
        movzx ebx, [@@y]
        movzx ecx, [@@type]

        call isPositionFree, eax, ebx
        cmp eax, 0
        je position_not_free
        ; call getEntityType, eax, ebx, offset dynamic_grid
        
        call getMainType, ecx

        cmp eax, -1
        je invalid_entity_spawn
        cmp eax, 255
        jge invalid_entity_spawn
        
        ; if it didn't jump, the position is valid
        cmp eax, 0 ; spawn plant
        je SpawnPlantType
        cmp eax, 1 ; spawn zombie
        je SpawnZombieType
        cmp eax, 2 ; spawn leap zombie
        je SpawnProjectileType

    invalid_entity_spawn:
        mov eax, 1 ; return 1 if the entity could not be spawned
        ret
SpawnZombieType:

    call getSubType, ecx

    cmp eax, 0
    je spawn_default_zombie
    cmp eax, 1
    je spawn_strong_zombie
    cmp eax, 2
    je spawn_leap_zombie
    
    ret

    spawn_default_zombie:
        movzx eax, [@@x]
        call spawnDefaultZombie, eax, ebx
        mov eax, 0 ; return 0 if the entity was spawned
        ret

    spawn_strong_zombie:
        movzx eax, [@@x]
        call spawnStrongZombie, eax, ebx
        mov eax, 0 ; return 0 if the entity was spawned
        ret

    spawn_leap_zombie:
        movzx eax, [@@x]
        call spawnLeapZombie, eax, ebx
        mov eax, 0 ; return 0 if the entity was spawned
        ret
SpawnPlantType:

    call getCost, ecx
    mov edx, [player_coins]
    cmp edx, eax
    jb not_enough_money
    sub edx, eax ;Subtract coins for spawning enity
    mov [player_coins], edx 

    call getSubType, ecx
    
    cmp eax, 0
    je spawn_default_plant
    cmp eax, 1
    je spawn_potato
    cmp eax, 2
    je spawn_bigger_potato
    cmp eax, 3
    je spawn_bigger_plant
    cmp eax, 4 
    je spawn_biggest_plant

    ret
    spawn_default_plant:
        movzx eax, [@@x]
        call spawnDefaultPlant, eax, ebx
        mov eax, 0 ; return 0 if the entity was spawned
        ret

    spawn_potato:
        movzx eax, [@@x]
        call spawnPotato, eax, ebx
        mov eax, 0 ; return 0 if the entity was spawned
        ret

    spawn_bigger_potato:
        movzx eax, [@@x]
        call spawnBiggerPotato, eax, ebx
        mov eax, 0 ; return 0 if the entity was spawned
        ret

    spawn_bigger_plant:
        movzx eax, [@@x]
        call spawnBiggerPlant, eax, ebx
        mov eax, 0 ; return 0 if the entity was spawned
        ret

    spawn_biggest_plant:
        movzx eax, [@@x]
        call spawnBiggestPlant, eax, ebx
        mov eax, 0 ; return 0 if the entity was spawned
        ret
SpawnProjectileType:
    spawn_projectile:
        movzx eax, [@@x]
        call spawnProjectile, eax, ebx
        mov eax, 0 ; return 0 if the entity was spawned
    
    ret
not_enough_money:
    ; return 1 if entity could not be spawned
    movzx eax, [@@x]
    movzx ebx, [@@y]
    call convertGridCoordsToPixelPosition, eax, ebx
    mov edx, TILE_WIDTH
    mov edi, TILE_HEIGHT
    mov ecx, 4 ; red color
    call drawColoredRectangle, eax, ebx, edx, edi, ecx
    ; Print melding
    call setCursorPosition, 2, 0
    mov edx, offset msg_no_coins
    call printString, edx

    mov eax, 1
    ret
position_not_free:
    ret
ENDP spawnEntityType

; function to find a free spot in the 9th column and spawn the entity
PROC findFreeSpotLastColumn
    ARG @@entityType:BYTE RETURNS eax
    LOCAL @@count:BYTE
    USES ebx, ecx, edx, esi, edi
    
    ; ; Check if the entity type is -1 or 255
    movzx eax, [@@entityType]
    cmp eax, -1
    je no_entity_spawn
    cmp eax, 255
    je no_entity_spawn

    call rand5

    ; This is a placeholder and should be replaced with your actual logic
    mov ecx, 9  ; 9th column index
    mov edx, eax  ; Start at the top row

find_free_spot_loop:
    ; Check if the spot is free 
    ; This is a placeholder condition
    call getEntityType, ecx, edx, offset dynamic_grid
    call getMainType, eax
    cmp al, -1
    je found_free_spot
    cmp al, 255
    je found_free_spot

    ; Move to the next row
    inc edx
    cmp edx, ROWS
    jne find_free_spot_loop

    ; No free spot found, return with an error code
    mov eax, 1
    ret

found_free_spot:
    ; Free spot found, spawn the entity 
    ; This is a placeholder spawn logic
    movzx eax, [@@entityType]
    add eax, 10
    
    call spawnEntityType, ecx, edx, eax
    mov eax, 0  ; Success
    ret
no_entity_spawn:
    mov eax, 0
    ret
; Call drawSpritePartial to draw a part of the sprite
ENDP findFreeSpotLastColumn

; function to handle the spawning of entities
PROC handleEntitySpawning
    USES eax, ebx, ecx, edx, edi, esi

        ; increment the spawn counter
        call incrementSpawnCounter
        cmp al, 0
        je not_spawn 

        ; get the current entity type
        mov ebx, [current_level]
        movzx eax, [current_wave]
        imul eax, 4                   ; Multiply wave index by 4 (size of a pointer)
        mov edx, [ebx + LEVEL.waves]
        add edx, eax
        mov edx, [edx]                ; Get the pointer to the current wave
        movzx ecx, [current_entity]
        add edx, ecx
        mov eax, [edx]              ; Get the entity type

        ;call spawnEntityType, 9, 0, eax ; TODO change the type of the entity, based on what is in the array
        call findFreeSpotLastColumn, eax
        cmp al, 1
        je not_spawn ; if the entity could not be spawned, do not increment the entity counter

        ; increment the entity counter
        call incrementEntityCounter
        cmp al, 0
        je not_spawn

        ; increment the wave counter
        call incrementWaveCounter
        cmp al, 0
        je not_spawn

        ; change the level if the wave counter was reset
        call incrementLevelCounter
        cmp al, 0
        je not_spawn
        ; if al contains 1, the last level was reached, end the game
        call terminateProcess

    not_spawn:
        ret

ENDP handleEntitySpawning

PROC spawnStartingEntities

    call spawnDefaultZombie, 8, 1
    call spawnDefaultZombie, 8, 2
    call spawnDefaultZombie, 8, 3
    call spawnDefaultZombie, 8, 4

    call spawnDefaultPlant, 0, 0
    call spawnDefaultPlant, 0, 1
    call spawnDefaultPlant, 0, 2
    call spawnPotato, 5, 3
    call spawnBiggerPotato, 5, 4
    call spawnBiggerPlant, 0, 3
    call spawnBiggestPlant, 0, 4
    ret
ENDP spawnStartingEntities
; --------------------------------------------------------------------------------------------------------------------------------------

; Interface functions

; --------------------------------------------------------------------------------------------------------------------------------------
; Calls the correct solver (shop/menu/...) based on region coordinates
PROC RegionSolver
    ARG @@mouseX:WORD, @@mouseY:WORD
    USES eax, ebx, ecx, edx, esi, edi

    mov esi, offset regions      ; Start address of the regions
    mov ecx, NUM_REGIONS         ; Number of regions to iterate through

check_next_region:
    cmp ecx, 0
    je short RegionSolver_no_region_found           ; No region found

    ; Check if mouseX is within x_min and x_max
    mov ax, [esi + REGION.x_min]
    cmp [@@mouseX], ax
    jl skip_to_next

    mov ax, [esi + REGION.x_max]
    cmp [@@mouseX], ax
    jg skip_to_next

    ; Check if mouseY is within y_min and y_max
    mov ax, [esi + REGION.y_min]
    cmp [@@mouseY], ax
    jl skip_to_next

    mov ax, [esi + REGION.y_max]
    cmp [@@mouseY], ax
    jg skip_to_next

    ; Region found, determine action based on region_type
    mov al, [esi + REGION.region_type]
    cmp al, 0
    je call_MenuSolver
    cmp al, 1
    je call_ShopSolver

    jmp end_RegionSolver

call_MenuSolver:
    call MenuSolver
    jmp end_RegionSolver

call_ShopSolver:
    call ShopSolver
    jmp end_RegionSolver

skip_to_next:
    add esi, REGION_SIZE      ; Go to the next region
    dec ecx
    jmp check_next_region

RegionSolver_no_region_found:
    ; No region found; optionally perform a default action
    jmp end_RegionSolver

end_RegionSolver:
    ret
ENDP RegionSolver

PROC ShopSolver
    USES eax, esi

    ; Set selected_shop to sub_type of the selected region
    mov al, [esi + REGION.sub_type]
    mov [selected_shop], al
    ret
    
ENDP ShopSolver

PROC MenuSolver
    mov al, [esi + REGION.sub_type]
    cmp al, 9
    jne no_menu_action
    call stopMusic
    call restartGame

    no_menu_action:
    ret
ENDP MenuSolver 


; Procedure to decide which spawn function to call based on selected_shop value
PROC SpawnSolver
    ARG @@coordX:WORD, @@coordY:WORD
    USES eax, ebx, ecx, edx
    
    ; Currently only spawning based on mainType, possible to extend to subType with switch cases
    mov al, [selected_shop]
    movzx eax, al
    call getMainType, eax

    cmp eax, -1
    je SpawnSolver_end

    cmp eax, 0
    je SpawnPlant
    
    cmp eax, 1
    je SpawnZombie
    

    ; If selected_shop has other values, do nothing
    jmp SpawnSolver_end

SpawnPlant:
    ; Spawn a plant at grid coordinates (@@coordX, @@coordY)
    movzx eax, [@@coordX]    ; Load coordX into EAX
    movzx ebx, [@@coordY]    ; Load coordY into EBX
    call printMouseCoordinates, eax, ebx
    call spawnDefaultPlant, eax, ebx

    jmp SpawnSolver_end

SpawnZombie:
    ; Spawn a zombie at grid coordinates (@@coordX, @@coordY)
    movzx eax, [@@coordX]    ; Load coordX into EAX
    movzx ebx, [@@coordY]    ; Load coordY into EBX
    call printMouseCoordinates, eax, ebx
    call spawnDefaultZombie, eax, ebx

    jmp SpawnSolver_end

SpawnSolver_end:
    ret
ENDP SpawnSolver
    
; resets selected_shop to 255 
PROC ShopReset
    USES eax

    mov al, -1
    mov [selected_shop], al
    ret

ENDP ShopReset

PROC drawShopInterface
    USES eax, ebx, ecx, edx, esi, edi, ebp

    mov esi, offset regions
    mov ecx, NUM_REGIONS

draw_shop_loop:
    cmp ecx, 0
    je done_shop

    ; Read coordinates of the region
    movzx eax, [esi + REGION.x_min]  ; eax = x_min
    movzx edx, [esi + REGION.x_max]  ; edx = x_max
    movzx ebx, [esi + REGION.y_min]  ; ebx = y_min
    movzx edi, [esi + REGION.y_max]  ; edi = y_max

    ; Width = x_max - x_min + 1
    sub edx, eax
    inc edx
    ; Height = y_max - y_min + 1
    sub edi, ebx
    inc edi

    ; Read the sub_type to determine which item (zombie/plant/...)
    movzx ebp, [esi + REGION.sub_type]  ; ebp = sub_type

    ; Check if this is a shop region (region_type = 1)
    cmp [esi + REGION.region_type], 1
    je shop_region
    cmp [esi + REGION.region_type], 0
    je menu_region
    jmp not_shop_region

shop_region:
    ;save eax
    push eax
    call getMainType, ebp
    cmp eax, 0
    
    je plant_button
    call getMainType, ebp
    cmp eax, 1
    
    je zombie_button
    pop eax
    ;restore eax and go to next region
    jmp not_shop_region
menu_region:
    push eax
    call getSubType, ebp
    cmp eax, 9
    je reset_button
    pop eax
    ;restore eax and go to next region
    jmp not_shop_region

zombie_button:
    pop eax

    mov ecx, 7  ; gray tint
    ; Draw the base button
    push ecx ; Save color value

    call drawColoredRectangle, eax, ebx, edx, edi, ecx
    pop ecx ; Restore color value

    call drawSprite, offset button6, VMEMADR, eax, ebx
    jmp after_entity_draw

reset_button:
    pop eax
    mov ecx, 1  ; blue tint 
    push ecx ; Save color value
    call drawColoredRectangle, eax, ebx, edx, edi, ecx
    pop ecx ; Restore color value
    call setCursorPosition, 22, 1
    call printString, offset msg_game_reset
    jmp after_entity_draw

plant_button:
    pop eax
    ; Draw the base button
    mov ecx, 2  ; green tint 
    push ecx ; Save color value
    call drawColoredRectangle, eax, ebx, edx, edi, ecx
    pop ecx ; Restore color value
    
    call getSubType, ebp
    cmp al, 0
    je draw_plant_button
    cmp al, 1
    je draw_potato_button
    cmp al, 2
    je draw_bigger_potato_button
    cmp al, 3
    je draw_bigger_plant_button
    cmp al, 4
    je SHORT draw_biggest_plant_button
    jmp SHORT after_entity_draw


draw_plant_button:
    movzx eax, [esi + REGION.x_min] 
    call drawSprite, offset button1, VMEMADR, eax, ebx
    jmp after_entity_draw

draw_potato_button:
    movzx eax, [esi + REGION.x_min] 
    call drawSprite, offset button4, VMEMADR, eax, ebx
    jmp after_entity_draw

draw_bigger_potato_button:
    movzx eax, [esi + REGION.x_min] 
    call drawSprite, offset button5, VMEMADR, eax, ebx
    jmp after_entity_draw

draw_bigger_plant_button:
    movzx eax, [esi + REGION.x_min] 
    call drawSprite, offset button2, VMEMADR, eax, ebx
    jmp after_entity_draw

draw_biggest_plant_button:
    movzx eax, [esi + REGION.x_min] 
    call drawSprite, offset button3, VMEMADR, eax, ebx

after_entity_draw:
    
 ; Check if this is the selected button
    push ecx
    movzx ecx, [selected_shop]
    cmp ebp, ecx
    pop ecx
    jne not_shop_region

    ; If selected, draw a white border
    mov ecx, 15                   ; Color for border
    push ecx
    call drawRectangle, eax, ebx, edx, edi, ecx
    pop ecx

not_shop_region:
    
    add esi, REGION_SIZE
    dec ecx
    jmp draw_shop_loop

done_shop:
    ret
ENDP drawShopInterface

PROC displayCoins
    USES eax, ebx, ecx, edx

    mov eax, [player_coins]
    call setCursorPosition, 20, 2
    call printDecimal, eax
    call drawCoin, 5, 158 

    ret
ENDP displayCoins

; Calculates the cost of an entity based on type (in AL)

PROC getCost
    ARG @@type:BYTE RETURNS eax
    USES ebx, ecx, edx

    movzx eax, [@@type]
    call getMainType, eax
    cmp al, 0
    jne no_cost ; only mainType=0 (plants) have a cost

    ; mainType=0 => plant
    ; now retrieve subType
    movzx eax, [@@type]
    call getSubType, eax

    cmp al, 0
        je get_cost_default_plant
        cmp al, 1
        je get_cost_potato
        cmp al, 2
        je get_cost_bigger_potato
        cmp al, 3
        je get_cost_bigger_plant
        cmp al, 4
        je get_cost_biggest_plant
    
        jmp no_cost
    
    get_cost_default_plant:
        movzx eax, [cost_default_plant]
        ret
    
    get_cost_potato:
        movzx eax, [cost_potato]
        ret
    
    get_cost_bigger_potato:
        movzx eax, [cost_bigger_potato]
        ret
    
    get_cost_bigger_plant:
        movzx eax, [cost_bigger_plant]
        ret
    
    get_cost_biggest_plant:
        movzx eax, [cost_biggest_plant]
        ret
    
    no_cost:
        mov eax, 0
        ret
ENDP getCost

PROC showGameOverScreen
    USES eax, ebx, ecx, edx, esi, edi

    call stopMusic

    ; Make black background
    call fillBackgroundFaster, 0

    ;Print Game Over and instructions for reset/exit
    call setCursorPosition, 10, 16
    mov edx, offset msg_gameover
    call printString, edx

    call setCursorPosition, 12, 10
    mov edx, offset msg_restart_instructions_restart
    call printString, edx
    call setCursorPosition, 13, 10
    mov edx, offset msg_restart_instructions_exit
    call printString, edx

GameOverInputLoop:
    ; Check ESC key
    call checkForSpecificKeystroke, 001Bh ; ESC

    ; Check 'R' key to Restart
    mov ah, 01h
    int 16h
    jz no_key_pressed_gameover
    
    mov ah, 00h
    int 16h
    cmp al, 'r'
    jne not_R_key
    
    ; 'R' was pressed --> restart game
    call restartGame
    ret

not_R_key:
    ;Neglect other keys
    jmp GameOverInputLoop

no_key_pressed_gameover:
    ; Option to add buttons
    ; call handleMouseClick
    jmp GameOverInputLoop

ENDP showGameOverScreen

;Restarts game (after GAME OVER)
PROC restartGame
    USES eax, ebx, ecx, edx, esi, edi
    
    ; Reset game-related variables
    mov [free_index], 0
    mov [current_level_index], 0
    mov [current_level], offset level1_instance
    mov [current_wave], 0
    mov [current_entity], 0
    mov [spawn_counter], 0
    mov [player_coins], 300      ; Initialize player coins to 300
    mov [player_hearts], 3       ; Initialize player hearts to 3
    mov [elapsed_time], 0         ; Reset elapsed time
    
    ; Clear the grid by setting all cells to -1
    mov edi, offset grid
    mov eax, ENTITY_SIZE
    imul eax, COLUMNS
    imul eax, ROWS
    mov ecx, eax
    mov al, -1
    rep stosb                      ; Fill grid with -1
    
    ; Clear the dynamic grid
    mov edi, offset dynamic_grid
    mov eax, COLUMNS
    imul eax, ROWS
    mov ecx, eax
    xor eax, eax
    mov al, -1
    rep stosb                      ; Fill dynamic_grid with -1
    
    ; Clear the dynamic entities array
    mov edi, offset dynamic_entities_array
    mov eax, ENTITY_SIZE
    imul eax, MAX_ENTITIES
    mov ecx, eax
    xor eax, eax
    mov al, -1
    rep stosb                      ; Fill dynamic_entities_array with -1
    
    ; Restart game music and timer
    call startMusic
    call startTime
    
    ; Spawn the initial set of entities
    call spawnStartingEntities
    
    ret
ENDP restartGame

; Draws a red heart at the specified (x0, y0) coordinates
PROC drawHeart
    ARG @@x0:WORD, @@y0:WORD
    USES eax, ebx, ecx, edx, edi, esi

    movzx eax, [@@x0]
    movzx ebx, [@@y0]
    mov ecx, 12 ; Color code for red

    ; Row0: Two small rectangles to form the top of the heart
    movzx eax, [@@x0]
    add eax, 2
    movzx edx, [@@y0]
    call drawColoredRectangle, eax, edx, 2, 1, ecx

    movzx eax, [@@x0]
    add eax, 6
    movzx edx, [@@y0]
    call drawColoredRectangle, eax, edx, 2, 1, ecx

    ; Row1: Middle wider rectangle
    movzx eax, [@@x0]
    add eax, 1
    movzx ebx, [@@y0]
    add ebx, 1
    call drawColoredRectangle, eax, ebx, 8, 1, ecx

    ; Rows2-4: Extending the heart shape downwards
    movzx eax, [@@x0]
    movzx ebx, [@@y0]
    add ebx, 2
    call drawColoredRectangle, eax, ebx, 10, 1, ecx

    movzx eax, [@@x0]
    movzx ebx, [@@y0]
    add ebx, 3
    call drawColoredRectangle, eax, ebx, 10, 1, ecx

    movzx eax, [@@x0]
    movzx ebx, [@@y0]
    add ebx, 4
    call drawColoredRectangle, eax, ebx, 10, 1, ecx

    ; Row5: Narrowing the heart again
    movzx eax, [@@x0]
    add eax, 1
    movzx ebx, [@@y0]
    add ebx, 5
    call drawColoredRectangle, eax, ebx, 8, 1, ecx

    ; Row6: Further narrowing
    movzx eax, [@@x0]
    add eax, 2
    movzx ebx, [@@y0]
    add ebx, 6
    call drawColoredRectangle, eax, ebx, 6, 1, ecx

    ; Row7: Almost at the bottom of the heart
    movzx eax, [@@x0]
    add eax, 3
    movzx ebx, [@@y0]
    add ebx, 7
    call drawColoredRectangle, eax, ebx, 4, 1, ecx

    ; Row8: Bottom of the heart
    movzx eax, [@@x0]
    add eax, 4
    movzx ebx, [@@y0]
    add ebx, 8
    call drawColoredRectangle, eax, ebx, 2, 1, ecx

    ret
ENDP drawHeart

; Displays the player's hearts on the screen
PROC displayHearts
    USES eax, ebx, ecx, edx, esi, edi

    mov eax, [player_hearts]
    cmp eax, 0
    je no_hearts

    mov ebx, 6   ; Starting x-coordinate for the first heart
    mov edx, 30  ; y-coordinate for hearts

    mov ecx, eax ; Number of hearts to display
draw_heart_loop:
    push ecx
    mov eax, ebx
    call drawHeart, eax, edx
    pop ecx
    add ebx, 14  ; Spacing between hearts
    loop draw_heart_loop

no_hearts:
    ret
ENDP displayHearts

; Draws a yellow coin at the specified (x0, y0) coordinates
PROC drawCoin
    ARG @@x0:WORD, @@y0:WORD
    USES eax, ebx, ecx, edx, edi, esi

    mov ecx, 14 ; Color code for yellow

    ; Row0: Top of the coin
    movzx eax, [@@x0]
    add eax, 3
    movzx edx, [@@y0]
    call drawColoredRectangle, eax, edx, 4, 1, ecx

    ; Row1: Expanding width
    movzx eax, [@@x0]
    add eax, 2
    movzx ebx, [@@y0]
    add ebx, 1
    call drawColoredRectangle, eax, ebx, 6, 1, ecx

    ; Rows2-3: Middle of the coin
    movzx eax, [@@x0]
    add eax, 1
    movzx ebx, [@@y0]
    add ebx, 2
    call drawColoredRectangle, eax, ebx, 8, 1, ecx

    movzx eax, [@@x0]
    add eax, 1
    movzx ebx, [@@y0]
    add ebx, 3
    call drawColoredRectangle, eax, ebx, 8, 1, ecx

    ; Rows4-5: Maintaining coin width
    movzx eax, [@@x0]
    movzx ebx, [@@y0]
    add ebx, 4
    call drawColoredRectangle, eax, ebx, 10, 1, ecx

    movzx eax, [@@x0]
    movzx ebx, [@@y0]
    add ebx, 5
    call drawColoredRectangle, eax, ebx, 10, 1, ecx

    ; Rows6-7: Narrowing the coin towards the bottom
    movzx eax, [@@x0]
    add eax, 1
    movzx ebx, [@@y0]
    add ebx, 6
    call drawColoredRectangle, eax, ebx, 8, 1, ecx

    movzx eax, [@@x0]
    add eax, 1
    movzx ebx, [@@y0]
    add ebx, 7
    call drawColoredRectangle, eax, ebx, 8, 1, ecx

    ; Row8: Bottom narrowing
    movzx eax, [@@x0]
    add eax, 2
    movzx ebx, [@@y0]
    add ebx, 8
    call drawColoredRectangle, eax, ebx, 6, 1, ecx

    ; Row9: Base of the coin
    movzx eax, [@@x0]
    add eax, 3
    movzx ebx, [@@y0]
    add ebx, 9
    call drawColoredRectangle, eax, ebx, 4, 1, ecx

    ret
ENDP drawCoin

; --------------------------------------------------------------------------------------------------------------------------------------

; Main game loop

; --------------------------------------------------------------------------------------------------------------------------------------
PROC main
    sti                 ; Enable interrupts
    cld                 ; Clear direction flag

    push ds
    pop	es

    call    mouse_present
    cmp     eax, 1
    je      @@mouse_present

    mov     ah, 9
    mov     edx, offset msg_no_mouse
    int     21h

@@mouse_present:
    ; Set video mode to 13h and install mouse handler
    call    setVideoMode, 13h
    call startMusic
    call    mouse_install, offset mouseHandler
    call    rand_init

    ; Load sprite files into memory
    lea eax, [sprite1+8] ; get memory location of first image data element in the sprite variable
    call ReadFile, offset sprite_file1, eax, DATASIZE ; Fill image data from file data
    lea eax, [sprite2+8]
    call ReadFile, offset sprite_file2, eax, DATASIZE
    lea eax, [sprite3+8]
    call ReadFile, offset sprite_file3, eax, DATASIZE
    lea eax, [sprite4+8]
    call ReadFile, offset sprite_file4, eax, DATASIZE
    lea eax, [sprite5+8]
    call ReadFile, offset sprite_file5, eax, DATASIZE
    lea eax, [sprite6+8]
    call ReadFile, offset sprite_file6, eax, DATASIZE
    lea eax, [sprite7+8]
    call ReadFile, offset sprite_file7, eax, DATASIZE
    lea eax, [sprite8+8]
    call ReadFile, offset sprite_file8, eax, DATASIZE
    lea eax, [sprite9+8]
    call ReadFile, offset sprite_file9, eax, DATASIZE

    ; Load button files into memory
    lea eax, [button1+8]
    call ReadFile, offset button_file1, eax, DATASIZE
    lea eax, [button2+8]
    call ReadFile, offset button_file2, eax, DATASIZE
    lea eax, [button3+8]
    call ReadFile, offset button_file3, eax, DATASIZE
    lea eax, [button4+8]
    call ReadFile, offset button_file4, eax, DATASIZE
    lea eax, [button5+8]
    call ReadFile, offset button_file5, eax, DATASIZE
    lea eax, [button6+8]
    call ReadFile, offset button_file6, eax, DATASIZE
    
    ; Initialize regions arguments: @@regionIndex:BYTE, @@x_min:WORD, @@x_max:WORD, @@y_min:WORD, @@y_max:WORD, @@region_type:BYTE, @@sub_type:BYTE
    call initializeRegion, 0, 0, 24, 50, 82, 1, 00
    call initializeRegion, 1, 0, 24, 83, 115, 1, 03
    call initializeRegion, 2, 0, 24, 116, 148, 1, 04
    call initializeRegion, 3, 25, 49, 50, 82, 1, 01
    call initializeRegion, 4, 25, 49, 83, 115, 1, 02
    call initializeRegion, 5, 25, 49, 116, 148, 1, 10
    call initializeRegion, 6, 5, 47, 172, 186, 0, 9

    ; Spawn initial entities
    call spawnStartingEntities
    call startTime

    ; Main game loop
@@gameLoop:
    ; Process other game logic
    call updateGameState

    ; Set mouseX and mouseY + print when MouseClick
    call handleMouseClick

    ; Render the frame
    call renderFrame

    ; Handle entity spawning
    call handleEntitySpawning

    ; Check and reset timer if necessary
    call checkAndResetTimer

    ; Check for ESC key to exit
    call checkForSpecificKeystroke, 001Bh
    jmp @@gameLoop
ENDP main

; -------------------------------------------------------------------

;Data & variables

; -------------------------------------------------------------------
DATASEG

    ; Entity structure definition
    STRUC ENTITY
        type            db -1    ; Type of entity (-1 indicates empty)
        health          db ?     ; Health of the entity
        damage          db ?     ; Damage dealt by the entity
        speed           db ?     ; Speed of the entity
        x               db ?     ; X position of the entity
        y               db ?     ; Y position of the entity
        direction       db ?     ; Direction of the entity
        animationFrame  db ?     ; Current animation frame
        animationTimer  db ?     ; Animation timer
        spriteIndex     db ?     ; Index of the sprite
        fireInterval    db ?     ; Interval between firing projectiles
        fireTimer       db ?     ; Timer for firing projectiles
    ENDS ENTITY

    ; Region structure definition
    STRUC REGION
        x_min       DW ?    ; Minimum X coordinate of the region
        x_max       DW ?    ; Maximum X coordinate of the region
        y_min       DW ?    ; Minimum Y coordinate of the region
        y_max       DW ?    ; Maximum Y coordinate of the region
        region_type DB ?    ; Type of the region (e.g., shop, menu)
        sub_type    DB ?    ; Sub-type of the region (e.g., specific button)
    ENDS REGION

    ; Palette for 256 colors (3 bytes per color)
    palette db 768 dup (?)

    ; Grid for static entities (5 rows * 10 columns)
    grid ENTITY 50 dup (<>)

    ; Dynamic grid for entities (5 rows * 10 columns)
    dynamic_grid db 50 dup (-1)

    ; Array for dynamic entities (space for 100 entities)
    dynamic_entities_array ENTITY 100 dup (<>)

    ; Index of the first free entity in the dynamic_entities_array
    free_index db 0

    ; Maximum number of entities in the dynamic_entities_array
    mob_capacity db 100

    ; Number of entities in the dynamic_entities_array
    mob_counter db 0

    ; Array for regions (space for max 20 regions)
    regions REGION 20 dup (<>)

    ; Buffer for BMP header and image data
    buffer db BMP_HEADER_SIZE + 320 * 200 dup (0)

    ; Messages for various purposes
    msg_unknown db "Unknown entity type", 10, 13, "$"
    msg_type db "free index is", 10, 13, "$"
    msg_no_mouse db 'No mouse found!', 0dh, 0ah, '$'
    msg_test db 'Test $'
    msg_wave_interval db "/", '$'

    ; Timer variables
    start_time dd 0
    elapsed_time dd 0

    ; Custom mouse handler pointer
    custom_mouse_handler dd ?

    ; Mouse coordinates
    mouseX dd 0
    mouseY dd 0

    ; Entities health & damage constants
    default_plant_health db 50
    potato_health db 154
    bigger_potato_health db 254
    bigger_plant_health db 200
    biggest_plant_health db 200

    ; Shop-related variables
    selected_shop db -1
    cost_default_plant db 50
    cost_potato db 25
    cost_bigger_potato db 75
    cost_bigger_plant db 100
    cost_biggest_plant db 150
    dead_zombie_reward dd 20

    ; Player-related variables
    player_coins dd 300   ; Start with 300 coins
    msg_coins db "Coins:", '$'
    msg_no_coins db "Broke times", 13, 10, "$"
    player_hearts dd 3
    msg_gameover db "GAME OVER", "$"
    msg_game_over db "GAME OVER", 13,10,'$',0
    msg_restart_instructions_restart db "Press 'R'   to restart",13,10,'$',0
    msg_restart_instructions_exit db "      'ESC' to exit",13,10,'$',0

    ; Menu-related messages
    msg_menu_restart db "Restart", "$"
    msg_menu_exit db "Exit", "$"
    msg_game_reset db "RESET", 0Dh, 0Ah, "$"
    msg_pause_menu db "Paused - Choose an option", "$"
    msg_pause_restart db "Restart Game", "$"
    msg_pause_setlevel db "Set Level", "$"
    msg_pause_return db "Return to Game", "$"

    ; Region structure offsets
    REGION_x_min       EQU 0
    REGION_x_max       EQU 2
    REGION_y_min       EQU 4
    REGION_y_max       EQU 6
    REGION_region_type EQU 8
    REGION_sub_type    EQU 9
    REGION_SIZE        EQU 10  ; Total size of REGION struct

    ; -------------------------------------------------------------------
    ; LEVELS

    STRUC LEVEL
        level_name dd ?      ; Pointer to the level name
        waves_count db ?     ; Number of waves
        waves dd ?           ; Pointer to the waves
    ENDS LEVEL

    level_array dd offset level1_instance, offset level2_instance, offset level3_instance, offset level4_instance, offset level5_instance, offset level6_instance, offset level7_instance, offset level8_instance

    current_level_index db 0 ; index of the current level
    current_level dd offset level1_instance ; pointer to the current level
    current_wave db 0 ; counter for the current wave
    current_entity db 0 ; counter for the current entity in the current wave
    wave_length db 15 ; length of waves
    spawn_counter db 0

    ; Level 1
    level1_name db "Level1", '$'
    level1_wave1 db -1, -1, 0, -1, 0, -1, -1, -1, 0, -1, -1, -1, 0, -1, -1
    level1_wave2 db -1, -1, 0, 0, -1, -1, -1, 0, -1, 0, -1, -1, -1, 0, -1
    level1_wave3 db -1, -1, -1, 0, -1, -1, -1, -1, 0, -1, -1, -1, 0, -1, -1
    level1_waves dd offset level1_wave1, offset level1_wave2, offset level1_wave3
    level1_instance LEVEL <offset level1_name, 3, level1_waves>


    ; Level 2
    level2_name db "Level2", '$'
    level2_wave1 db 0, -1, 0, -1, 0, -1, 0, -1, -1, 0, -1, 0, -1, -1, -1
    level2_wave2 db -1, 0, 1, -1, 0, -1, 0, 1, -1, 0, -1, -1, 0, -1, -1
    level2_wave3 db -1, 0, 0, -1, 1, -1, 0, -1, -1, 0, 0, -1, 1, -1, 0
    level2_wave4 db -1, -1, 1, -1, 0, -1, -1, -1, 0, -1, -1, -1, 1, -1, 0
    level2_waves dd offset level2_wave1, offset level2_wave2, offset level2_wave3, offset level2_wave4
    level2_instance LEVEL <offset level2_name, 4, level2_waves>

    ; Level 3
    level3_name db "Level3", '$'
    level3_wave1 db -1, 0, 0, -1, 1, -1, 0, 0, -1, 0, -1, 1, 0, -1, 0
    level3_wave2 db 0, 1, 1, -1, 0, -1, -1, 2, 1, -1, 0, -1, 0, -1, 1
    level3_wave3 db 0, 1, -1, -1, 1, -1, 0, -1, -1, 0, -1, 2, 0, -1, 1
    level3_waves dd offset level3_wave1, offset level3_wave2, offset level3_wave3
    level3_instance LEVEL <offset level3_name, 3, level3_waves>

    ; Level 4
    level4_name db "Level4", '$'
    level4_wave1 db 0, 1, 0, -1, 0, 1, 2, -1, 0, 1, 0, -1, 1, -1, 2
    level4_wave2 db 0, 2, -1, 1, 0, -1, 2, 1, 0, -1, 0, 2, -1, 1, 1
    level4_waves dd offset level4_wave1, offset level4_wave2
    level4_instance LEVEL <offset level4_name, 2, level4_waves>

    ; Level 5
    level5_name db "Level5", '$'
    level5_wave1 db 0, 0, 2, -1, 2, -1, 1, 2, -1, 0, -1, 2, 0, -1, 1
    level5_wave2 db 1, 2, -1, 1, 1, 2, -1, 0, 2, -1, 0, 2, 1, -1, 1
    level5_wave3 db 0, 2, 1, -1, 1, -1, 0, -1, 2, -1, 0, 1, 2, 1, -1
    level5_waves dd offset level5_wave1, offset level5_wave2, offset level5_wave3
    level5_instance LEVEL <offset level5_name, 3, level5_waves>

    ; Level 6
    level6_name db "Level6", '$'
    level6_wave1 db 2, 1, 1, -1, 0, 2, 1, -1, 1, 2, -1, 2, 0, 1, 2
    level6_wave2 db 2, 1, -1, 2, 2, -1, 1, 0, 2, -1, 2, 1, -1, 2, 1
    level6_waves dd offset level6_wave1, offset level6_wave2
    level6_instance LEVEL <offset level6_name, 2, level6_waves>

    ; Level 7
    level7_name db "Level7", '$'
    level7_wave1 db 2, 2, 1, 2, 2, 1, 2, 1, 1, 2, 2, 1, 1, 2, 2
    level7_wave2 db 2, 2, 1, 2, 2, 1, 2, 2, 1, 2, 2, 1, 2, 2, 1
    level7_waves dd offset level7_wave1, offset level7_wave2
    level7_instance LEVEL <offset level7_name, 2, level7_waves>

    ; Level 8
    level8_name db "Level8", '$'
    level8_wave1 db 2, 2, 2, 1, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 2
    level8_wave2 db 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2
    level8_waves dd offset level8_wave1, offset level8_wave2
    level8_instance LEVEL <offset level8_name, 2, level8_waves>

    ; SPRITES
    ; Plants
    sprite_file1 db "sprites/SPRITEDP.bin", 0 ; default plant
    sprite_file6 db "sprites/SPRITEDQ.bin", 0 ; potato
    sprite_file7 db "sprites/SPRITEDR.bin", 0 ; bigger pea shooter
    sprite_file8 db "sprites/SPRITEDS.bin", 0 ; bigger potato
    sprite_file9 db "sprites/SPRITEDT.bin", 0 ; biggest pea shooter

    ; Projectile
    sprite_file2 db "sprites/SPRITEDA.bin", 0
    ; Zombies
    sprite_file3 db "sprites/SPRITEDC.bin", 0 ; default zombie
    sprite_file4 db "sprites/SPRITEDD.bin", 0 ; strong zombie
    sprite_file5 db "sprites/SPRITEDF.bin", 0 ; leap zombie
    ; BUTTONS
    ; Button Files
    button_file1 db "sprites/defplant.bin", 0     ; Bigger Plant Button
    button_file2 db "sprites/bigplant.bin", 0    ; Biggest Plant Button
    button_file3 db "sprites/maxplant.bin", 0        ; Default Plant Button
    button_file4 db "sprites/potato.bin", 0           ; Potato Button
    button_file5 db "sprites/potato2.bin", 0          ; Second Potato Button
    button_file6 db "sprites/zombie.bin", 0           ; Zombie Button

	openErrorMsg db "could not open file", 13, 10, '$'
	readErrorMsg db "could not read data", 13, 10, '$'
	closeErrorMsg db "error during file closing", 13, 10, '$'

	sprite1 DD SPRITEWIDTH, SPRITEHEIGHT
    DB DATASIZE DUP(0)

    sprite2 DD SPRITEWIDTH, SPRITEHEIGHT
    DB DATASIZE DUP(0)

    sprite3 DD SPRITEWIDTH, SPRITEHEIGHT
    DB DATASIZE DUP(0)

    sprite4 DD SPRITEWIDTH, SPRITEHEIGHT
    DB DATASIZE DUP(0)

    sprite5 DD SPRITEWIDTH, SPRITEHEIGHT
    DB DATASIZE DUP(0)

    sprite6 DD SPRITEWIDTH, SPRITEHEIGHT
    DB DATASIZE DUP(0)

    sprite7 DD SPRITEWIDTH, SPRITEHEIGHT
    DB DATASIZE DUP(0)

    sprite8 DD SPRITEWIDTH, SPRITEHEIGHT
    DB DATASIZE DUP(0)

    sprite9 DD SPRITEWIDTH, SPRITEHEIGHT
    DB DATASIZE DUP(0)

    button1 DD BUTTONWIDTH, BUTTONHEIGHT
    DB BUTTONSIZE DUP(0)

    button2 DD BUTTONWIDTH, BUTTONHEIGHT
    DB BUTTONSIZE DUP(0)

    button3 DD BUTTONWIDTH, BUTTONHEIGHT
    DB BUTTONSIZE DUP(0)

    button4 DD BUTTONWIDTH, BUTTONHEIGHT
    DB BUTTONSIZE DUP(0)

    button5 DD BUTTONWIDTH, BUTTONHEIGHT
    DB BUTTONSIZE DUP(0)

    button6 DD BUTTONWIDTH, BUTTONHEIGHT
    DB BUTTONSIZE DUP(0)
 

    ; AUDIO
    sound_file db "audio/loop.RAW", 0
	buffhalf db 1	; what buffer half has to be copied
	musicPlaying db 0
	readbusy dw 0	; if busy reading something else
	readfail dw 0 	; signal if interrupt was called during busy time
    
; -------------------------------------------------------------------
; STACK
; -------------------------------------------------------------------
STACK 2000h

END main
