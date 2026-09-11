# Project IP configuration

This directory stores editable Anlogic IP Generator configuration files used as regeneration inputs. Generated vendor wrappers are kept under the appropriate `src/vendor/` or project wrapper boundary after verification.

- `p1_hdmi_pll_50m_75_375.ipc`: P1-04A EG4S20 PLL request, 50 MHz input -> 75 MHz C0 + 375 MHz C1 at 90°. Before board use, open/regenerate it with **TD5.6.2** and compare the generated primitive parameters with `src/top/p1_hdmi_pll_50m.v`; the checked-in RTL is a candidate, not a substitute for the generator evidence.
