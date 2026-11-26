; L19_StockRun, for L19_Stock: Call(p, blk) calls the procedure p as on a
; stock 65C816, the core's banked direct page and stack off (WDM #$B0): D
; and S in blk, a 2 KB block of bank 0 (D at blk + $10, off a page; S from
; blk + $7FE), the caller's direct page copied to D's. Then D and S back,
; banked again. Interrupts are off meanwhile.

    cpu="816"
    longa=on
    longi=on

    .proc Call(LONGINT, LONGINT)

tgt      = $02          ; the procedure, a long pointer
blk      = $06          ; the block, 2 KB in bank 0: D at + $10, S at + $7FE

    section "text"

Call*:
    php
    sei
    ldy #$10            ; the direct page into the block's
    ldx #0
.cp:
    lda $00,x
    sta [blk],y
    iny
    iny
    inx
    inx
    cpx #$100
    bne .cp
    ldy #0              ; D and S kept at the block's start
    tdc
    sta [blk],y
    ldy #2
    tsc
    sta [blk],y
    lda blk
    clc
    adc #$7FE
    tax
    lda blk
    clc
    adc #$10
    wdm #$B0            ; banked off: D and S are bank 0's
    tcd
    txa
    tcs
    phk                 ; JSL [tgt]: the return, then the target less 1 for RTL
    per .back-1
    sep #$20
    lda tgt+2
    pha
    rep #$20
    lda tgt
    dec a
    pha
    rtl
.back:
    tdc                 ; the block, from D
    sec
    sbc #$10
    tax
    lda.l $000002,x     ; S
    tay
    lda.l $000000,x     ; D
    wdm #$B1            ; banked again
    tcd
    tya
    tcs
    plp
    rtl
