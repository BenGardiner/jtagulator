  {{
  Program Description:
   
  Secondary mode for the JTAGulator -- converts it to a SUMP compatible logic analyzer. e.g. Openbench Logic Sniffer
  }}
   
   
CON                             
  MAX_INPUT_LEN                 = 5 ' SUMP long commands are five bytes
  MAX_SAMPLE_BYTES              = 4096
  MAX_PROBES                    = 24
  MAX_CH_GROUPS                 = MAX_PROBES / 8
  MAX_SAMPLE_PERIODS            = MAX_SAMPLE_BYTES / 4 'We capture 32bits at a time keep the sampler cog fast(er than it would be otherwise)
                                                       'TODO: don't waste 25% of the buffer *AND* get a >1Msps max sample rate :)

  ' used to convert between the OLS 100MHz clock and the JTAGulator's 80MHz clock
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
  DEFAULT_DELAY_PERIODS         = DEFAULT_READ_PERIODS
  DEFAULT_DISABLE_FLAGS         = %00100000 ' disable ch group 4

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

  long sampleBuffer[MAX_SAMPLE_BYTES]
 
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

  led.Init
  led.Yellow           

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
            led.Off
            samplerState:=ARM
            repeat until (samplerState == OFF)
            led.Yellow
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

              'TODO: support readPeriods > delayPeriods (i.e. capturing pre-trigger window)
              if readPeriods > delayPeriods
                readPeriods := delayPeriods
                                
            CMD_DIV:
              larg:=vCmd[3]
              larg<<=8
              larg|=vCmd[2]
              larg<<=8
              larg|=vCmd[1]

              clocksWait:=((larg+1)*SR_FACTOR_NUM)/SR_FACTOR_DEN
            
            CMD_FLAGS:
              disableFlags:=vCmd[1] & DISABLE_FLAGS_MASK            

PRI SendAllSamples | i 'NB: OLS sends samples in reverse
  i := 0
  repeat while i < readPeriods
    SendSamples(sampleBuffer[delayPeriods - i++])

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
        
'using SPIN for this sampler is limiting the stable sample rate to ~5k ; above this the waitcnt() waits for wrap
PUB Sampler(dummy) | stamp, values, samplerCount
  repeat
    case samplerState
      OFF:
        'hot-wait

      ARM:
        samplerState:=ARMED
        'todo assign triggering parameters

      ARMED:
        'TODO: sample (for pre-trigger) and check states wait for trigger using waitpeq()
        samplerState:=TRIGGER

      TRIGGER:
        samplerState:=TRIGGERED
        led.Init
        led.Red
        stamp:=cnt

      TRIGGERED:
        samplerState:=SAMPLING
        samplerCount:=delayPeriods
        led.Yellow
          
      SAMPLING:
        values:=ina[23..0]
        led.Progress 
        sampleBuffer[delayPeriods - samplerCount] := values
        if samplerCount-- =< 1
          samplerState:=OFF
          led.Off
        waitcnt(stamp+=clocksWait)                    
 
DAT
ID            byte "1ALS"

METADATA      byte $01, "JTAGulator", $00 ' device name
              byte $02, "0.0.0", $00      ' firmware version
              byte $03, "0.0", $00        ' ancilliary version
              byte $21
              byte $00, $00, $0c, $00     ' sample memory 3072 in MSB -- must match MAX_SAMPLE_PERIODS*MAX_CH_GROUPS
              byte $23
              byte $04, $C4, $B4, $00     ' 80_000_000 in MSB -- TODO: set to highest stable SR
              byte $40
              byte MAX_PROBES             ' number of probes
              byte $41
              byte $02                    ' protocol version 2
END_METADATA  byte $00