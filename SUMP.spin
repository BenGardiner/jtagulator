  {{
  Program Description:
   
  Secondary mode for the JTAGulator -- converts it to a SUMP compatible logic analyzer. e.g. Openbench Logic Sniffer
   
  Supported Commands (of http://www.sump.org/projects/analyzer/protocol/):
  0x00 - reset
  0x01 - query id
  }}
   
   
CON
  MAX_INPUT_LEN                 = 5 ' SUMP long commands are five bytes
  MAX_SAMPLES_BYTES             = 24576
  MAX_SAMPLE_RATE               = 80_000_000
  MAX_PROBES                    = 24             
 
  CMD_RESET       = $00 ' reset command
  CMD_QUERY_ID    = $02 ' query id                
  CMD_QUERY_META  = $04 'query metadata
    
VAR                   ' Globally accessible variables
  byte vCmd[MAX_INPUT_LEN + 1]  ' Buffer for command input string
 
OBJ
  ser           : "PropSerial"  
  led           : "LED"
 
PUB Go | firstByte                                                                                                                         
  ser.Start(115_200)            ' Start serial communications. TODO: up the baud rate
  ' Start command receive/process cycle
  led.Red                       ' Set status indicator to show that we're ready
  repeat
    firstByte := ser.CharInNoEcho            ' Wait here to receive a single byte                          
    led.Progress
     
    case firstByte
      CMD_RESET:
        led.Green

      CMD_QUERY_ID:
        ser.StrMax(@ID, strsize(@ID) + 1)

      CMD_QUERY_META:
        ser.StrMax(@METADATA, @END_METADATA - @METADATA + 1)
      
      other:
        led.Red      
 
DAT
ID            byte "1ALS", 0

METADATA      byte $01, "JTAGulator", 0
              byte $02, "0.0", 0
              byte $20
              long MAX_PROBES             ' number of probes
              byte $21
              long MAX_SAMPLES_BYTES      ' sample memory available (bytes)
              byte $23
              long MAX_SAMPLE_RATE        ' max sample rate
              byte $40, MAX_PROBES        ' number of probes (short version)
              byte $41, 2                 ' protocol version
END_METADATA  byte $00