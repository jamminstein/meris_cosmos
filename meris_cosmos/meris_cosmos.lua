-- meris_cosmos.lua
-- Norns script to control Meris LVX, ENZO, POLYMOON, MERCURY 7, OTTOBIT JR
-- via MIDI CC. Requires a MIDI interface connected to the pedals.
--
-- SETUP:
--   Set each pedal to MIDI mode (hold Alt on power-up, select MIDI):
--     LVX      → ch 1
--     ENZO     → ch 2
--     POLYMOON → ch 3
--     MERCURY7 → ch 4
--     OTTOBIT  → ch 5
--   Connect norns MIDI out → Meris MIDI I/O (or TRS adapter) → pedals.
--
-- CONTROLS:
--   E1 → select pedal
--   E2 → select preset (1-8)
--   E3 → randomize current pedal (musically constrained)
--   K1 → panic: safe-init all pedals
--   K2 → send selected preset to selected pedal
--   K3 → toggle auto-morph (slow LFO across wet/mod params)
--
-- TEMPO SYNC:
--   Follows the Norns system clock (set via params > CLOCK, or locked to
--   Ableton Link / MIDI clock in / crow). On every clock pulse:
--     POLYMOON, MERCURY7 → MIDI 0xF8 clock byte (24 PPQ)
--     LVX, OTTOBIT       → tap CC pulse + direct time CC
--     ENZO               → delay time CC set to one quarter note (ms)
--   Params page: "MIDI clock out" to disable the 0xF8 stream if needed.

engine.name = "None"

local midi_out
local midi_out_device = 1

-- ─── MIDI channel assignments ─────────────────────────────────
local CH = { LVX=1, ENZO=2, POLYMOON=3, MERCURY7=4, OTTOBIT=5 }

-- ─── CC maps ──────────────────────────────────────────────────

local OB_CC = {
  bypass=14, tempo=15, smpl_rate=16, filter=17, bits=18,
  stutter=19, stutter_hold=31, sequencer=20, seq_mult=21,
  seq_type=29,
  step1=22, step2=23, step3=24,
  step4=25, step5=26, step6=27,
  tap=28
}

local M7_CC = {
  bypass=14, space_decay=16, modulate=17, mix=18,
  lo_freq=19, pitch_vector=20, hi_freq=21, predelay=22,
  mod_speed=23, pitch_vector_mix=24, density=25,
  attack_time=26, vibrato_depth=27, swell=28, algorithm=29
}

local PM_CC = {
  bypass=14, time=16, feedback=17, mix=18, multiply=19,
  dimension=20, dynamics=21, early_mod=22, feedback_filter=23,
  delay_level=24, late_mod=25, dyn_flanger_mode=26,
  dyn_flanger_speed=27, phaser_mode=29, flanger_feedback=30,
  half_speed=31
}

local LVX_CC = {
  mix=1, bypass=14, time=15, delay_type=16,
  left_div=17, right_div=18, feedback=19,
  cross_feedback=20, delay_mod=21,
  preamp_type=5, preamp_p1=7, preamp_p2=8,
  tap=99
}

local EN_CC = {
  bypass=14, pitch=16, filter=17, mix=18, sustain=19,
  filter_env=20, modulation=21, portamento=22, filter_type=23,
  delay_level=24, filter_bw=25, ring_mod=26, delay_fb=27,
  synth_mode=28, waveshape=29
}

-- ─── Helpers ──────────────────────────────────────────────────
local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
local function rnd(lo,hi) return math.floor(lo + math.random()*(hi-lo)) end

local function preset(cc_map, ...)
  local t, args = {}, {...}
  for i=1,#args,2 do
    local k,v = args[i], args[i+1]
    if cc_map[k] then table.insert(t,{cc=cc_map[k],val=v}) end
  end
  return t
end

-- ─── Curated presets ──────────────────────────────────────────
local PRESETS = {

  OTTOBIT = {
    { name="SID Chip Arp",
      data=preset(OB_CC,
        "bypass",127, "smpl_rate",90, "filter",70, "bits",30,
        "stutter",40, "sequencer",127,
        "seq_mult",50, "seq_type",100,
        "step1",64, "step2",80, "step3",96,
        "step4",64, "step5",50, "step6",40) },
    { name="Glitch Filter Seq",
      data=preset(OB_CC,
        "bypass",127, "smpl_rate",127, "filter",50, "bits",110,
        "stutter",0, "sequencer",127,
        "seq_mult",64, "seq_type",60,
        "step1",20, "step2",60, "step3",100,
        "step4",127, "step5",80, "step6",30) },
    { name="Lo-Fi Crush",
      data=preset(OB_CC,
        "bypass",127, "smpl_rate",20, "filter",90, "bits",15,
        "stutter",0, "sequencer",0, "seq_mult",64, "seq_type",0) },
    { name="Rhythmic Stutter",
      data=preset(OB_CC,
        "bypass",127, "smpl_rate",80, "filter",80, "bits",80,
        "stutter",60, "sequencer",127,
        "seq_mult",30, "seq_type",20,
        "step1",100, "step2",60, "step3",100,
        "step4",40, "step5",100, "step6",0) },
    { name="Warm Tape Crush",
      data=preset(OB_CC,
        "bypass",127, "smpl_rate",100, "filter",100, "bits",60,
        "stutter",0, "sequencer",0, "seq_mult",64, "seq_type",0) },
    { name="Max Headroom",
      data=preset(OB_CC,
        "bypass",127, "smpl_rate",60, "filter",40, "bits",50,
        "stutter",90, "stutter_hold",0,
        "sequencer",0, "seq_mult",64) },
    { name="Pitch Seq Melody",
      data=preset(OB_CC,
        "bypass",127, "smpl_rate",110, "filter",75, "bits",90,
        "stutter",0, "sequencer",127,
        "seq_mult",64, "seq_type",110,
        "step1",64, "step2",72, "step3",76,
        "step4",84, "step5",64, "step6",56) },
    { name="Ring Mod Mayhem",
      data=preset(OB_CC,
        "bypass",127, "smpl_rate",80, "filter",60, "bits",100,
        "stutter",30, "sequencer",127,
        "seq_mult",127, "seq_type",20,
        "step1",80, "step2",90, "step3",100,
        "step4",110, "step5",120, "step6",127) },
  },

  MERCURY7 = {
    { name="Blade Runner Plate",
      data=preset(M7_CC,
        "bypass",127, "algorithm",0,
        "space_decay",110, "modulate",60, "mix",80,
        "lo_freq",90, "hi_freq",50, "pitch_vector",64,
        "predelay",20, "mod_speed",30, "density",80,
        "pitch_vector_mix",64, "vibrato_depth",20) },
    { name="Cathedral",
      data=preset(M7_CC,
        "bypass",127, "algorithm",127,
        "space_decay",127, "modulate",80, "mix",90,
        "lo_freq",110, "hi_freq",40, "pitch_vector",80,
        "predelay",60, "mod_speed",20, "density",100,
        "pitch_vector_mix",80, "vibrato_depth",40) },
    { name="Shimmer 8va",
      data=preset(M7_CC,
        "bypass",127, "algorithm",127,
        "space_decay",100, "modulate",50, "mix",70,
        "lo_freq",80, "hi_freq",80, "pitch_vector",110,
        "predelay",10, "mod_speed",60, "density",90,
        "pitch_vector_mix",100, "vibrato_depth",50) },
    { name="Subtle Room",
      data=preset(M7_CC,
        "bypass",127, "algorithm",0,
        "space_decay",50, "modulate",20, "mix",40,
        "lo_freq",60, "hi_freq",70, "pitch_vector",64,
        "predelay",5, "mod_speed",15, "density",60,
        "pitch_vector_mix",20, "vibrato_depth",0) },
    { name="Frozen Sky",
      data=preset(M7_CC,
        "bypass",127, "algorithm",127,
        "space_decay",127, "modulate",90, "mix",100,
        "lo_freq",127, "hi_freq",30, "pitch_vector",90,
        "predelay",80, "mod_speed",10, "density",127,
        "pitch_vector_mix",110, "vibrato_depth",70, "swell",127) },
    { name="Spring Warm",
      data=preset(M7_CC,
        "bypass",127, "algorithm",0,
        "space_decay",70, "modulate",35, "mix",55,
        "lo_freq",100, "hi_freq",60, "pitch_vector",64,
        "predelay",15, "mod_speed",45, "density",70,
        "pitch_vector_mix",30, "vibrato_depth",10) },
    { name="Infinite Swell",
      data=preset(M7_CC,
        "bypass",127, "algorithm",127,
        "space_decay",127, "modulate",60, "mix",90,
        "lo_freq",110, "hi_freq",50, "pitch_vector",64,
        "predelay",40, "mod_speed",8, "density",110,
        "pitch_vector_mix",64, "vibrato_depth",30,
        "swell",127, "attack_time",80) },
    { name="Eerie 5th",
      data=preset(M7_CC,
        "bypass",127, "algorithm",0,
        "space_decay",90, "modulate",70, "mix",75,
        "lo_freq",80, "hi_freq",60, "pitch_vector",90,
        "predelay",25, "mod_speed",25, "density",85,
        "pitch_vector_mix",90, "vibrato_depth",55) },
  },

  ENZO = {
    { name="PolySwell Pad",
      data=preset(EN_CC,
        "bypass",127, "synth_mode",20, "waveshape",30,
        "pitch",64, "filter",40, "mix",90, "sustain",100,
        "filter_env",60, "modulation",50,
        "portamento",40, "filter_type",20,
        "delay_level",70, "delay_fb",50) },
    { name="Mono Lead",
      data=preset(EN_CC,
        "bypass",127, "synth_mode",50, "waveshape",100,
        "pitch",64, "filter",90, "mix",80, "sustain",55,
        "filter_env",80, "modulation",30,
        "portamento",10, "filter_type",60,
        "delay_level",50, "delay_fb",35) },
    { name="SparkArp",
      data=preset(EN_CC,
        "bypass",127, "synth_mode",80, "waveshape",100,
        "pitch",64, "filter",70, "mix",85, "sustain",40,
        "filter_env",100, "modulation",60,
        "portamento",0, "filter_type",80,
        "delay_level",80, "delay_fb",60) },
    { name="Dark Arp Bass",
      data=preset(EN_CC,
        "bypass",127, "synth_mode",80, "waveshape",100,
        "pitch",40, "filter",25, "mix",90, "sustain",50,
        "filter_env",90, "modulation",20,
        "portamento",5, "filter_type",30,
        "delay_level",60, "delay_fb",40) },
    { name="Bell Tines",
      data=preset(EN_CC,
        "bypass",127, "synth_mode",20, "waveshape",30,
        "pitch",64, "filter",100, "mix",70, "sustain",30,
        "filter_env",127, "modulation",40,
        "portamento",0, "filter_type",90,
        "delay_level",60, "delay_fb",30) },
    { name="Ring Drone",
      data=preset(EN_CC,
        "bypass",127, "synth_mode",20, "waveshape",30,
        "pitch",64, "filter",30, "mix",85, "sustain",120,
        "filter_env",30, "modulation",70,
        "portamento",60, "ring_mod",80,
        "delay_level",90, "delay_fb",70) },
    { name="PolyGlide Strings",
      data=preset(EN_CC,
        "bypass",127, "synth_mode",20, "waveshape",30,
        "pitch",64, "filter",55, "mix",80, "sustain",100,
        "filter_env",50, "modulation",55,
        "portamento",90, "filter_type",40,
        "delay_level",75, "delay_fb",55) },
    { name="Dry Pitch Shift",
      data=preset(EN_CC,
        "bypass",127, "synth_mode",110, "waveshape",30,
        "pitch",80, "filter",75, "mix",65, "sustain",60,
        "filter_env",40, "modulation",35,
        "portamento",0, "filter_type",50,
        "delay_level",55, "delay_fb",40) },
  },

  POLYMOON = {
    { name="Cosmic Slop",
      data=preset(PM_CC,
        "bypass",127, "time",70, "feedback",80, "mix",85,
        "multiply",90, "dimension",100, "dynamics",60,
        "early_mod",80, "feedback_filter",64,
        "late_mod",90, "dyn_flanger_mode",64,
        "dyn_flanger_speed",50, "phaser_mode",64,
        "flanger_feedback",60) },
    { name="Holdsworth Trails",
      data=preset(PM_CC,
        "bypass",127, "time",100, "feedback",90, "mix",70,
        "multiply",80, "dimension",80, "dynamics",80,
        "early_mod",60, "feedback_filter",80,
        "late_mod",70, "dyn_flanger_mode",40,
        "dyn_flanger_speed",30, "phaser_mode",100,
        "flanger_feedback",40) },
    { name="Barberpole Dream",
      data=preset(PM_CC,
        "bypass",127, "time",50, "feedback",60, "mix",75,
        "multiply",70, "dimension",90, "dynamics",50,
        "early_mod",110, "feedback_filter",50,
        "late_mod",100, "dyn_flanger_mode",80,
        "dyn_flanger_speed",70, "phaser_mode",127,
        "flanger_feedback",80) },
    { name="Slapback Lo-Fi",
      data=preset(PM_CC,
        "bypass",127, "time",20, "feedback",25, "mix",50,
        "multiply",30, "dimension",40, "dynamics",40,
        "early_mod",20, "feedback_filter",40,
        "late_mod",15, "dyn_flanger_mode",10,
        "dyn_flanger_speed",10, "phaser_mode",0,
        "flanger_feedback",20) },
    { name="Half-Speed Wash",
      data=preset(PM_CC,
        "bypass",127, "time",90, "feedback",100, "mix",90,
        "multiply",100, "dimension",110, "dynamics",90,
        "early_mod",90, "feedback_filter",64,
        "late_mod",110, "dyn_flanger_mode",90,
        "dyn_flanger_speed",80, "phaser_mode",80,
        "flanger_feedback",70, "half_speed",127) },
    { name="Dense Shimmer",
      data=preset(PM_CC,
        "bypass",127, "time",110, "feedback",110, "mix",80,
        "multiply",120, "dimension",120, "dynamics",70,
        "early_mod",100, "feedback_filter",90,
        "late_mod",100, "dyn_flanger_mode",60,
        "dyn_flanger_speed",60, "phaser_mode",60) },
    { name="Stereo Ping Pong",
      data=preset(PM_CC,
        "bypass",127, "time",60, "feedback",70, "mix",65,
        "multiply",50, "dimension",70, "dynamics",55,
        "early_mod",50, "feedback_filter",64,
        "late_mod",60, "dyn_flanger_mode",30,
        "dyn_flanger_speed",20) },
    { name="Zappa Feedback",
      data=preset(PM_CC,
        "bypass",127, "time",80, "feedback",120, "mix",95,
        "multiply",110, "dimension",127, "dynamics",100,
        "early_mod",120, "feedback_filter",110,
        "late_mod",120, "dyn_flanger_mode",100,
        "dyn_flanger_speed",90, "phaser_mode",110,
        "flanger_feedback",110) },
  },

  LVX = {
    { name="Digital Clean",
      data=preset(LVX_CC,
        "bypass",127, "mix",60, "time",70,
        "delay_type",0, "feedback",50, "cross_feedback",0,
        "delay_mod",30, "left_div",64, "right_div",64) },
    { name="BBD Analog",
      data=preset(LVX_CC,
        "bypass",127, "mix",65, "time",80,
        "delay_type",40, "feedback",65, "cross_feedback",10,
        "delay_mod",50, "left_div",64, "right_div",90) },
    { name="Tape Saturation",
      data=preset(LVX_CC,
        "bypass",127, "mix",70, "time",90,
        "delay_type",80, "feedback",80, "cross_feedback",20,
        "delay_mod",60, "preamp_type",40, "preamp_p1",80,
        "preamp_p2",60) },
    { name="Polymoon Poly",
      data=preset(LVX_CC,
        "bypass",127, "mix",75, "time",100,
        "delay_type",110, "feedback",90, "cross_feedback",40,
        "delay_mod",80, "left_div",80, "right_div",110) },
    { name="Multitap Scatter",
      data=preset(LVX_CC,
        "bypass",127, "mix",80, "time",60,
        "delay_type",64, "feedback",60, "cross_feedback",30,
        "delay_mod",70, "left_div",50, "right_div",70) },
    { name="Reverse Dream",
      data=preset(LVX_CC,
        "bypass",127, "mix",85, "time",110,
        "delay_type",90, "feedback",100, "cross_feedback",50,
        "delay_mod",90) },
    { name="Subtle Slapback",
      data=preset(LVX_CC,
        "bypass",127, "mix",40, "time",25,
        "delay_type",0, "feedback",20, "cross_feedback",0,
        "delay_mod",10) },
    { name="Infinite Pad",
      data=preset(LVX_CC,
        "bypass",127, "mix",100, "time",127,
        "delay_type",80, "feedback",127, "cross_feedback",60,
        "delay_mod",100, "preamp_type",60, "preamp_p1",90) },
  },
}

-- ─── Musical randomization ranges ────────────────────────────
local RAND_RULES = {
  OTTOBIT = {
    smpl_rate={30,127}, filter={20,110}, bits={20,110},
    stutter={0,80}, seq_mult={20,90},
    step1={44,84}, step2={44,84}, step3={44,84},
    step4={44,84}, step5={44,84}, step6={0,84},
  },
  MERCURY7 = {
    space_decay={40,120}, modulate={10,90}, mix={40,100},
    lo_freq={30,110}, hi_freq={30,100}, pitch_vector={40,110},
    predelay={0,80}, mod_speed={5,80}, density={40,127},
    pitch_vector_mix={20,100}, vibrato_depth={0,60},
  },
  ENZO = {
    pitch={44,84}, filter={20,110}, mix={60,100},
    sustain={30,110}, filter_env={20,110}, modulation={10,80},
    portamento={0,80}, delay_level={40,100}, delay_fb={20,80},
    filter_bw={30,100}, ring_mod={0,70},
  },
  POLYMOON = {
    time={20,120}, feedback={20,105}, mix={40,100},
    multiply={20,110}, dimension={30,120}, dynamics={20,100},
    early_mod={10,110}, feedback_filter={30,100},
    late_mod={10,110}, dyn_flanger_mode={0,127},
    dyn_flanger_speed={10,90}, phaser_mode={0,127},
    flanger_feedback={0,90},
  },
  LVX = {
    mix={40,100}, time={20,120}, feedback={20,100},
    cross_feedback={0,60}, delay_mod={10,100},
  },
}

-- ─── State ───────────────────────────────────────────────────
local pedal_names   = {"LVX","ENZO","POLYMOON","MERCURY7","OTTOBIT"}
local sel_pedal     = 1
local sel_preset    = 1
local auto_morph    = false
local morph_phase   = 0
local morph_metro   = metro.init()
local last_params   = {}
local clock_enabled = true
local clock_co      = nil   -- the clock coroutine handle

-- ─── MIDI helpers ─────────────────────────────────────────────
local function send_cc(ch,cc,val)
  if midi_out then midi_out:cc(cc, math.floor(val), ch) end
end

-- ─── Tempo-dependent CC helpers ───────────────────────────────
-- OTTOBIT tempo CC and LVX time CC: both use 10ms units (0-127 → 0-1270ms).
local function bpm_to_10ms(bpm)
  return clamp(math.floor((60000 / bpm) / 10), 0, 127)
end

-- Enzo delay time CC: 0-127 maps linearly across 0-530ms.
local function bpm_to_enzo_delay(bpm)
  local ms = math.min(60000 / bpm, 530)
  return clamp(math.floor((ms / 530) * 127), 0, 127)
end

-- Send a tap CC pulse to LVX (CC99) and OTTOBIT (CC28).
-- A 0-value follow-up after 50ms completes the tap gesture.
local function send_tap_pulse()
  send_cc(CH.LVX,     LVX_CC.tap, 127)
  send_cc(CH.OTTOBIT, OB_CC.tap,  127)
  clock.run(function()
    clock.sleep(0.05)
    send_cc(CH.LVX,     LVX_CC.tap, 0)
    send_cc(CH.OTTOBIT, OB_CC.tap,  0)
  end)
end

-- Push current Norns BPM to all pedals via CC (called once on tempo change).
local function push_tempo_ccs()
  local bpm = params:get("clock_tempo")
  send_tap_pulse()
  send_cc(CH.LVX,     LVX_CC.time,  bpm_to_10ms(bpm))
  send_cc(CH.OTTOBIT, OB_CC.tempo,  bpm_to_10ms(bpm))
  send_cc(CH.ENZO,    EN_CC.pitch,  bpm_to_enzo_delay(bpm))
end

-- ─── MIDI clock coroutine ─────────────────────────────────────
-- Runs forever, firing 24 pulses per beat by syncing to 1/24 of a beat.
-- clock.sync() automatically tracks whatever the Norns clock source is
-- (internal, Link, MIDI in, crow), so BPM changes are followed for free.
local function clock_coroutine()
  while true do
    clock.sync(1/24)
    if clock_enabled and midi_out then
      midi_out:clock()
    end
  end
end

-- ─── Preset / panic helpers ───────────────────────────────────
local function send_preset(name, idx)
  local ch = CH[name]
  local p  = PRESETS[name][idx]
  if not p then return end
  last_params[name] = p.data
  for _,msg in ipairs(p.data) do send_cc(ch, msg.cc, msg.val) end
  print("→ "..name.." ch"..ch..": "..p.name)
end

local function panic_init()
  for _,name in ipairs(pedal_names) do
    local ch = CH[name]
    send_cc(ch,14,0)
    send_cc(ch,18,64)
    if name=="MERCURY7" then send_cc(ch,16,64)
    elseif name=="ENZO" then
      send_cc(ch,19,64) send_cc(ch,17,64)
    else send_cc(ch,19,50) end
  end
  print("PANIC: all pedals safe-init")
end

-- ─── Randomizer ───────────────────────────────────────────────
local function randomize_pedal(name)
  local rules  = RAND_RULES[name]
  local ch     = CH[name]
  local cc_map = ({LVX=LVX_CC,ENZO=EN_CC,POLYMOON=PM_CC,MERCURY7=M7_CC,OTTOBIT=OB_CC})[name]
  send_cc(ch,14,127)
  local sent = {}
  for param,range in pairs(rules) do
    local v = rnd(range[1],range[2])
    if cc_map[param] then
      send_cc(ch,cc_map[param],v)
      table.insert(sent,{cc=cc_map[param],val=v})
    end
  end
  last_params[name] = sent
  print("RND "..name)
end

-- ─── Auto-morph ───────────────────────────────────────────────
morph_metro.event = function()
  morph_phase = (morph_phase + 0.015) % (2*math.pi)
  local lfo = (math.sin(morph_phase)+1)/2

  send_cc(CH.MERCURY7, M7_CC.mix,       clamp(40+lfo*60,0,127))
  send_cc(CH.MERCURY7, M7_CC.modulate,  clamp(20+lfo*80,0,127))
  send_cc(CH.ENZO,     EN_CC.filter,    clamp(20+lfo*90,0,127))
  send_cc(CH.ENZO,     EN_CC.modulation,clamp(15+lfo*70,0,127))
  send_cc(CH.POLYMOON, PM_CC.dimension, clamp(40+lfo*70,0,127))
  send_cc(CH.POLYMOON, PM_CC.late_mod,  clamp(20+lfo*90,0,127))
  send_cc(CH.LVX,      LVX_CC.delay_mod,clamp(10+lfo*80,0,127))
  send_cc(CH.OTTOBIT,  OB_CC.filter,    clamp(30+lfo*80,0,127))
  send_cc(CH.OTTOBIT,  OB_CC.smpl_rate, clamp(50+lfo*60,0,127))

  redraw()
end

-- ─── Display ──────────────────────────────────────────────────
local function draw_bar(x,y,val,w,h)
  local fill = math.floor((val/127)*w)
  screen.rect(x,y,w,h) screen.level(3) screen.fill()
  screen.rect(x,y,fill,h) screen.level(15) screen.fill()
end

function redraw()
  screen.clear()
  local pname = pedal_names[sel_pedal]
  local pset  = PRESETS[pname][sel_preset]

  screen.level(15) screen.font_face(1) screen.font_size(8)
  screen.move(0,8) screen.text("MERIS COSMOS")
  screen.level(5) screen.move(84,8) screen.text("ch"..CH[pname])

  for i,n in ipairs(pedal_names) do
    screen.level(i==sel_pedal and 15 or 4)
    screen.move((i-1)*32,18) screen.text(n:sub(1,4))
  end

  screen.level(12) screen.move(0,30)
  screen.text(sel_preset..": "..(pset and pset.name or "---"))

  local p = last_params[pname] or (pset and pset.data) or {}
  for i=1,math.min(#p,12) do
    draw_bar((i-1)*10, 38, p[i].val, 8, 6)
  end

  -- tempo display (read live from Norns clock)
  local bpm = params:get("clock_tempo")
  screen.level(clock_enabled and 12 or 4)
  screen.move(0,50)
  screen.text(string.format("BPM:%.1f %s", bpm, clock_enabled and "CLK" or "clk"))

  screen.level(3) screen.move(0,58)
  screen.text("E1:pdl E2:pst K2:snd K3:morph E3:rnd")

  if auto_morph then
    screen.level(15) screen.move(118,58) screen.text("~")
  end

  screen.update()
end

-- ─── Encoders ─────────────────────────────────────────────────
function enc(n,d)
  if n==1 then
    sel_pedal  = clamp(sel_pedal+d,1,#pedal_names)
    sel_preset = 1
  elseif n==2 then
    sel_preset = clamp(sel_preset+d,1,#PRESETS[pedal_names[sel_pedal]])
  elseif n==3 then
    randomize_pedal(pedal_names[sel_pedal])
  end
  redraw()
end

-- ─── Keys ─────────────────────────────────────────────────────
function key(n,z)
  if z~=1 then return end
  if n==1 then
    panic_init()
  elseif n==2 then
    send_preset(pedal_names[sel_pedal], sel_preset)
  elseif n==3 then
    auto_morph = not auto_morph
    if auto_morph then morph_metro.time=0.05; morph_metro:start()
    else morph_metro:stop() end
  end
  redraw()
end

-- ─── Params ───────────────────────────────────────────────────
function init()
  params:add_number("midi_out_device","MIDI out device",1,4,1)
  params:set_action("midi_out_device",function(v)
    midi_out_device = v
    midi_out = midi.connect(v)
    print("MIDI out → device "..v)
  end)

  params:add_number("lvx_ch",      "LVX MIDI ch",     1,16,1)
  params:add_number("enzo_ch",     "ENZO MIDI ch",    1,16,2)
  params:add_number("polymoon_ch", "POLYMOON MIDI ch",1,16,3)
  params:add_number("m7_ch",       "MERCURY7 MIDI ch",1,16,4)
  params:add_number("ob_ch",       "OTTOBIT MIDI ch", 1,16,5)

  local ch_map = {
    lvx_ch="LVX", enzo_ch="ENZO", polymoon_ch="POLYMOON",
    m7_ch="MERCURY7", ob_ch="OTTOBIT"
  }
  for k,v in pairs(ch_map) do
    params:set_action(k,function(val) CH[v]=val end)
  end

  params:add_separator("clock_sep","── Clock ──")

  -- Hook into the Norns system clock_tempo param so any tempo change
  -- (via params page, crow, Link, or MIDI in) triggers a CC push.
  params:set_action("clock_tempo", function(_)
    push_tempo_ccs()
    redraw()
  end)

  params:add_option("clock_out","MIDI clock out",{"on","off"},1)
  params:set_action("clock_out",function(v)
    clock_enabled = (v==1)
    print("MIDI clock out: "..(clock_enabled and "ON" or "OFF"))
    redraw()
  end)

  params:bang()
  midi_out = midi.connect(midi_out_device)
  math.randomseed(os.time())

  -- Start the clock coroutine — it runs for the lifetime of the script.
  clock_co = clock.run(clock_coroutine)

  -- Push current tempo to all pedals on startup.
  push_tempo_ccs()

  print("meris_cosmos loaded")
  print("K2=send  K3=morph  K1=panic")
  print("E1=pedal  E2=preset  E3=randomize")
  print("Tempo follows NORNS CLOCK (params > CLOCK or system clock source)")
  redraw()
end

function cleanup()
  morph_metro:stop()
  if clock_co then clock.cancel(clock_co) end
end