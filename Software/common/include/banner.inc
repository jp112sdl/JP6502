; The name this machine signs on with. Three places emit it and they have to
; agree, so the text lives here and nowhere else:
;
;   * QT_BASIC in init.s - the sign-on line on the console
;   * sd_lcdbanner in db6502_sdbasic.s - the top row of the LCD panel
;   * ms_basic in rom/microsoft_basic/standalone.s - LCD and VDP at reset
;
; It stays a text macro rather than one shared label because the first of the
; three sits inside the MS-BASIC message table, which is walked as a run of
; bytes - that copy has to be there literally, so the other two would be the
; only ones able to share, for sixteen bytes and a dependency across objects.
;
; Keep it to 20 characters, the width of the LCD.
.define BASIC_BANNER "Microsoft BASIC"
