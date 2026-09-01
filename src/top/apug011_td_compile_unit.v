// ================================================================
// DEPRECATED / DO NOT ADD TO TD SYNTHESIS SOURCES
//
// Historical P1-02B compatibility shim.  It used `include to place
// global_def.v and the three APUG011 protected .enc.v files in one
// compilation unit.  Real TD 6.2.1 testing proved that this organization
// is incorrect for TangDynasty protected-source handling.
//
// TD 6.2.1 must instead mirror the official APUG011 v1.2 project:
//   1) src/vendor/anlogic/apug011/include/global_def.v
//        -> project source with GlobalIncluded=true
//   2) sdr_as_ram.enc.v / sdr_init_ref.enc.v / sdr_wrrd.enc.v
//        -> three independent Verilog project sources
//
// This file intentionally contains no module and no `include directives.
// It remains only as an audit trail so an old workspace cannot silently
// reintroduce the protected-core include shim.
// ================================================================
