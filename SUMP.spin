  {{
  Program Description:
   
  Secondary mode for the JTAGulator -- converts it to a SUMP compatible logic analyzer. e.g. Openbench Logic Sniffer
  }}
   
   
CON                             
  MAX_INPUT_LEN                 = 5 ' SUMP long commands are five bytes
  MAX_SAMPLE_PERIODS            = 4096
  MAX_SAMPLE_RATE               = 80_000_000
  MAX_PROBES                    = 24
  SR_FACTOR_NUM                 = 4 ' 80E6/100E6 = 4/5
  SR_FACTOR_DEN                 = 5             
 
  CMD_RESET                     = $00
  CMD_RUN                       = $01
  CMD_QUERY_ID                  = $02               
  CMD_QUERY_META                = $04
  CMD_QUERY_INPUT_DATA          = $06
  CMD_DIV                       = $80
  CMD_CNT                       = $81
  CMD_FLAGS                     = $82

  #0                            ' input processing states
  IDLE
  CHAIN

  #0                            'the sampler states
  OFF
  ARM
  ARMED
  TRIGGER
  TRIGGERED
  SAMPLING  

  DEFAULT_CLOCKS_WAIT           = 32 '2.5 MHz
  DEFAULT_READ_PERIODS          = MAX_SAMPLE_PERIODS 
  DEFAULT_DELAY_PERIODS         = 0
  DEFAULT_DISABLE_FLAGS         = 0

  DISABLE_FLAGS_MASK            = %00111100
    
VAR
  byte vCmd[MAX_INPUT_LEN + 1]  ' Buffer for command input string
  long larg
  long clocksWait
  long readPeriods
  long delayPeriods
  byte disableFlags

  byte samplerState
  long samplerStack[64]

  long sampleBuffer[MAX_SAMPLE_PERIODS]
 
OBJ
  ser           : "PropSerial"  
  led           : "LED"
 
PUB Go | firstByte, state, count, coggood, i                                                                                                                         
  ser.Start(115_200)            ' Start serial communications
  ' Start command receive/process cycle
  dira[23..0]~                  ' Set P23-P0 as inputs
  state:=IDLE
  samplerState:=OFF

  clocksWait:=DEFAULT_CLOCKS_WAIT
  readPeriods:=DEFAULT_READ_PERIODS
  delayPeriods:=DEFAULT_DELAY_PERIODS
  disableFlags:=DEFAULT_DISABLE_FLAGS           

  coggood:=cognew(Sampler(@samplerState), @samplerStack)
  if coggood =< 0
    ser.Str(String("Failed to start SUMP Sampler"))
    return

  repeat
    firstByte := ser.CharInNoEcho
     
    case state
      IDLE:
        case firstByte
          CMD_RESET:
          'do nothing
           samplerState:=OFF
             repeat while i < MAX_SAMPLE_PERIODS
                sampleBuffer[i++] := %01101001

          CMD_QUERY_ID, $31:
            ser.StrMax(@ID, @METADATA - @ID)
         
          CMD_QUERY_META:
            ser.StrMax(@METADATA, @END_METADATA - @METADATA + 1)
         
          CMD_QUERY_INPUT_DATA: 
            SendSamples(ina[23..0])

          CMD_RUN:
            samplerState:=TRIGGER
            repeat until (samplerState == OFF)
            SendAllSamples
          
          other:
            count:=0
            vCmd[0]:=firstByte
            state:=CHAIN

      CHAIN:
        count++
        vCmd[count]:=firstByte                               
        if count == MAX_INPUT_LEN - 1
          state:=IDLE

          case vCmd[0]
            CMD_CNT:
              larg:=vCmd[2]
              larg<<=8
              larg|=vCmd[1]
              readPeriods:=(larg+1)*4 'the protocol doesn't indicate the +1 is needed; but sigrok's ols api does
              if readPeriods > MAX_SAMPLE_PERIODS
                readPeriods:=MAX_SAMPLE_PERIODS 

              larg:=vCmd[4]
              larg<<=8
              larg|=vCmd[3]
              delayPeriods:=(larg+1)*4 'the protocol doesn't indicate the +1 is needed; but sigrok's ols api does
                                
            CMD_DIV:
              larg:=vCmd[3]
              larg<<=8
              larg|=vCmd[2]
              larg<<=8
              larg|=vCmd[1]

              clocksWait:=((larg+1)*SR_FACTOR_NUM)/SR_FACTOR_DEN
            
            CMD_FLAGS:
              disableFlags:=vCmd[1] & DISABLE_FLAGS_MASK            

PRI SendAllSamples | i
  i := 0
  repeat while i < readPeriods
    SendSamples(sampleBuffer[i++])

PRI SendSamples(value) | b
  'bits:            %76543210
  'ch disable flag:  --4321--
  if disableFlags & %00000100 == 0
    b:=(value) & $FF
    ser.Char(b) 
  'ch disable flag:  --4321--
  if disableFlags & %00001000 == 0
    b:=(value >> 8) & $FF
    ser.Char(b)    
  'ch disable flag:  --4321--
  if disableFlags & %00010000 == 0
    b:=(value >> 16) & $FF
    ser.Char(b)
  'ch disable flag:  --4321--
  if disableFlags & %00100000 == 0
    b:=0
    ser.Char(b)
        
PUB Sampler(dummy) | stamp, values, samplerCount
  repeat
    stamp:=cnt
    values:=ina[23..0]
    case samplerState
      OFF:
        'hot-wait

      ARM:
        samplerState:=ARMED
        'todo assign triggering parameters

      ARMED:
        'hot-wait
        'todo check states wait for trigger using waitpeq()
        samplerState:=TRIGGER

      TRIGGER:
        samplerCount:=delayPeriods
        samplerState:=TRIGGERED

      TRIGGERED:
        if samplerCount-- =< 1
          samplerCount:=readPeriods
          samplerState:=SAMPLING
        if cnt > clocksWait + stamp
          next
        waitcnt(clocksWait + stamp)
          
      SAMPLING:
        sampleBuffer[readPeriods - samplerCount] := values
        if samplerCount-- =< 1
          samplerState:=OFF
        if cnt > clocksWait + stamp
          next 
        waitcnt(clocksWait + stamp)                    
 
DAT
ID            byte "1ALS"

METADATA      byte $01, "JTAGulator", $00 ' device name
              byte $02, "0.0.0", $00      ' firmware version
              byte $03, "0.0", $00        ' ancilliary version
              byte $21
              byte $00, $00, $10, $00     ' sample memory 4096 in MSB -- must match MAX_SAMPLE_PERIOD
              byte $23
              byte $04, $C4, $B4, $00     ' 80_000_000 in MSB -- must match MAX_SAMPLE_RATE
              byte $40
              byte MAX_PROBES             ' number of probes
              byte $41
              byte $02                    ' protocol version 2
END_METADATA  byte $00