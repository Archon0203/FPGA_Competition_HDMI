# NOTE: QuestaSim 10.7c command-line -do sessions may exit after the first
# nested vsim/quit sequence.  Use the four standalone scripts instead:
#   run_sdram_adapter_apug011_0deg.do
#   run_sdram_adapter_apug011_90deg.do
#   run_sdram_adapter_apug011_180deg.do
#   run_sdram_adapter_apug011_270deg.do
# Canonical acceptance remains run_sdram_adapter_apug011_official.do (180deg).
puts "INFO: use standalone APUG011 phase scripts; no nested vsim sweep is run."
quit -f
