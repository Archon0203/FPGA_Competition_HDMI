# M2 Master TD vendor-IP project fix (2026-10-05)

Scope: project metadata only. RTL, constraints, vendor encrypted sources, protocol, UI and resource logic are unchanged.

The active Master top is `m2_master_tf_hdmi_top`. The previous GUI project metadata listed Anlogic APUG011/APUG092 protected sources after the project wrappers and did not mark `global_def.v` as a TD global include. TD therefore analyzed wrapper instantiations while `sdr_as_ram`, `hdmi_1_4b_transmitter_core_wrapper` and `hdmi_phy_wrapper` were unresolved, producing black-box errors.

This fix:

- marks `src/vendor/anlogic/apug011/include/global_def.v` as `GlobalIncluded=true`;
- orders APUG092 protected core -> LVDS lane -> HDMI PHY -> project wrappers;
- orders APUG011 protected SDRAM source before `apug011_core_wrapper.v`;
- keeps `m2_master_tf_hdmi_top` as the active top;
- removes the stale Master `_Runs` cache so the next TD synthesis starts from a clean analysis database;
- leaves every RTL and constraint file byte-identical to the source set recorded by `evidence/M2_MASTER_OUTPUT_20261004/master_manifest.json`.

After extraction, open `FPGA_Competition_HDMI_MASTER.al` and run a fresh Synthesis. Do not re-add vendor source files manually.
