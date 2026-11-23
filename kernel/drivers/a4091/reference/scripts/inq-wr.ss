;
; inq-wr.ss -- table-indirect SCSI SCRIPTS for the A4091 (NCR 53C710),
; READ *and* WRITE capable: the DATA phase dispatches on the LIVE bus phase the
; target enters after the command:
;   DATA_OUT -> send  (WRITE)   |   DATA_IN -> receive (READ)   |   none -> STATUS
; Both directions transfer ds_Data1 ({nbyte,addr} from the DSA); the 53C710 MOVE
; direction comes from the phase opcode, so the C side needs no change.
;
; The driver's src/a4091-wr.c inq_script[] is this file's output (inq-wr.out),
; byte for byte.  Assembled with NetBSD's ncr53cxxx:  ncr53cxxx inq-wr.ss -o inq-wr.out
;
; Synchronous negotiation (param sync=1): the driver sends IDENTIFY and an SDTR
; extended message in one MESSAGE OUT move (ds_MsgOut, 6 bytes).  A target that
; answers goes to MESSAGE IN: an SDTR answer (01 03 01 period offset) stops at
; INT neg_sdtr_v with the period and offset in ds_SyncMsg (the driver sets SXFER
; and SBCL, then continues at neg_ack); MESSAGE REJECT stops at INT neg_rej_v
; (the driver keeps the target asynchronous, then continues at command_phase);
; any other message stops at INT neg_other_v (continued at neg_ack).  A target
; that ignores the SDTR goes straight to COMMAND, as with IDENTIFY alone.
;
ARCH 710
;
; --- DSA table offsets (table-indirect), identical to inq.ss / siop_script.ss ---
ABSOLUTE ds_Device	= 0
ABSOLUTE ds_MsgOut	= ds_Device + 4
ABSOLUTE ds_Cmd		= ds_MsgOut + 8
ABSOLUTE ds_Status	= ds_Cmd + 8
ABSOLUTE ds_Msg		= ds_Status + 8
ABSOLUTE ds_MsgIn	= ds_Msg + 8
ABSOLUTE ds_ExtMsg	= ds_MsgIn + 8
ABSOLUTE ds_SyncMsg	= ds_ExtMsg + 8
ABSOLUTE ds_Data1	= ds_SyncMsg + 8
;
; --- result vectors ---
ABSOLUTE ok		= 0xff00
ABSOLUTE seltimeout_v	= 0xff10
ABSOLUTE err5		= 0xff05
ABSOLUTE neg_sdtr_v	= 0xff20
ABSOLUTE neg_rej_v	= 0xff21
ABSOLUTE neg_other_v	= 0xff22
;
ENTRY	scripts
ENTRY	command_phase
ENTRY	datadisp
ENTRY	seltimeout
ENTRY	neg_ack

PROC	scripts:

scripts:
	SELECT ATN FROM ds_Device, REL(seltimeout)
;
; MESSAGE OUT: IDENTIFY (ATN already asserted by SELECT), with an SDTR when
; negotiating; a target answering a message goes to MESSAGE IN
msgout:
	JUMP REL(err_phase), WHEN NOT MSG_OUT
	MOVE FROM ds_MsgOut, WHEN MSG_OUT
	JUMP REL(neg_in), WHEN MSG_IN
;
; COMMAND: drop ATN, send the CDB
command_phase:
	JUMP REL(err_phase), WHEN NOT CMD
	CLEAR ATN
	MOVE FROM ds_Cmd, WHEN CMD
;
; DATA: dispatch on the phase the target actually enters (also the short-read
; recovery's re-entry: it drains STATUS and MESSAGE IN to a clean INT ok)
datadisp:
	JUMP REL(dataout), WHEN DATA_OUT
	JUMP REL(datain), WHEN DATA_IN
	JUMP REL(status_phase), WHEN STATUS	; command with no data phase
	JUMP REL(msgin), WHEN MSG_IN		; a non-STATUS phase after the command
	JUMP REL(err_phase)			; anything else
dataout:
	MOVE FROM ds_Data1, WHEN DATA_OUT
	JUMP REL(status_phase)
datain:
	MOVE FROM ds_Data1, WHEN DATA_IN
;
; STATUS: receive the 1 status byte
status_phase:
	JUMP REL(err_phase), WHEN NOT STATUS
	MOVE FROM ds_Status, WHEN STATUS
;
; MESSAGE IN: receive COMMAND COMPLETE, ack, wait for disconnect
msgin:
	JUMP REL(err_phase), WHEN NOT MSG_IN
	MOVE FROM ds_Msg, WHEN MSG_IN
	CLEAR ACK
	WAIT DISCONNECT
	INT ok

err_phase:
	INT err5			; unexpected SCSI phase

seltimeout:
	INT seltimeout_v		; selection failed / reselected
;
; The answer to the message out: first byte to ds_MsgIn
neg_in:
	MOVE FROM ds_MsgIn, WHEN MSG_IN
	JUMP REL(neg_ext), IF 0x01	; extended message
	JUMP REL(neg_rej), IF 0x07	; MESSAGE REJECT
	INT neg_other_v
neg_rej:
	CLEAR ATN
	CLEAR ACK
	INT neg_rej_v			; continued at command_phase
neg_ext:
	CLEAR ACK
	MOVE FROM ds_ExtMsg, WHEN MSG_IN	; its length
	JUMP REL(neg_sdtr), IF 0x03
	INT neg_other_v
neg_sdtr:
	CLEAR ACK
	MOVE FROM ds_SyncMsg, WHEN MSG_IN	; 01 period offset
	INT neg_sdtr_v			; the driver sets SXFER and SBCL
neg_ack:
	CLEAR ATN
	CLEAR ACK
	JUMP REL(command_phase)
