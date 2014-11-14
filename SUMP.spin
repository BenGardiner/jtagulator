  {{
  Program Description:
   
  Secondary mode for the JTAGulator -- converts it to a SUMP compatible logic analyzer. e.g. Openbench Logic Sniffer
   
  Supported Commands (of http://www.sump.org/projects/analyzer/protocol/):
  0x00 - reset
  0x01 - query id
  }}
   
   
CON                             
  MAX_INPUT_LEN                 = 5 ' SUMP long commands are five bytes
  MAX_SAMPLES_BYTES             = 4096
  MAX_SAMPLE_RATE               = 80_000_000
  MAX_PROBES                    = 24             
 
  CMD_RESET                     = $00
  CMD_QUERY_ID                  = $02               
  CMD_QUERY_META                = $04
  CMD_QUERY_INPUT_DATA          = $06
  CMD_DIV                       = $80
  CMD_CNT                       = $81
  CMD_FLAGS                     = $82

  #0                            ' input processing states
  IDLE
  CHAIN
    
VAR
  byte vCmd[MAX_INPUT_LEN + 1]  ' Buffer for command input string
 
OBJ
  ser           : "PropSerial"  
  led           : "LED"
 
PUB Go | firstByte, state, count                                                                                                                         
  ser.Start(115_200)            ' Start serial communications. TODO: up the baud rate
  ' Start command receive/process cycle
  dira[23..0]~                  ' Set P23-P0 as inputs
  state:=IDLE

  led.Red                       ' Set status indicator to show that we're ready
  repeat
    firstByte := ser.CharInNoEcho            ' Wait here to receive a single byte                          
    led.Progress
     
    case state
      IDLE:
        case firstByte
          CMD_RESET:
            led.Green
                                          
          CMD_QUERY_ID, $31:
            ser.StrMax(@ID, @METADATA - @ID)
         
          CMD_QUERY_META:
            ser.StrMax(@METADATA, @END_METADATA - @METADATA + 1)
         
          CMD_QUERY_INPUT_DATA:
            SendSamples
          
          other:
            count:=0
            vCmd[0]:=firstByte
            state:=CHAIN
      CHAIN:
        count++
        vCmd[count]:=firstByte                               
        if count == MAX_INPUT_LEN
          state:=IDLE
          case vCmd[0]
            CMD_CNT:
            CMD_DIV:
            CMD_FLAGS:            

PRI SendSamples | b, value
  value := ina[23..0]     ' Read all channels
  'todo if 24-31 are enabled
  b:=0
  ser.Char(@b)
  'todo if 16-23 are enabled
  b:=(value >> 16) & $FF
  ser.Char(@b)
  'todo if 8-17 are enabled
  b:=(value >> 8) & $FF
  ser.Char(@b) 
  'todo if 0-7 are enabled
  b:=(value) & $FF
  ser.Char(@b) 

DAT
ID            byte "1ALS"

METADATA      byte $01, "JTAGulator", $00       ' device name
              byte $02, "0.0.0", $00      ' firmware version
              byte $03, "0.0", $00        ' ancilliary version
              byte $21
              byte $00, $00, $10, $00     ' sample memory 4096 in MSB
              byte $22
              byte $00, $00, $10, $00     ' dynamic memory 4096 in MSB
              byte $23
              byte $00, $2d, $c6, $c0     ' 3_000_000 in MSB
              byte $40
              byte MAX_PROBES             ' number of probes
              byte $41
              byte $02                    ' protocol version 2
END_METADATA  byte $00