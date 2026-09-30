<?xml version="1.0" encoding="UTF-8"?>
<Project Version="3" Minor="2" Path="D:/AnlogicProject/FPGA_Competition_HDMI/validation">
    <Project_Created_Time></Project_Created_Time>
    <TD_Encoding>UTF-8</TD_Encoding>
    <TD_Version>6.2.168116</TD_Version>
    <UCode>00000000</UCode>
    <Name>M1A_Timing</Name>
    <HardWare><Family>EG4</Family><Device>EG4S20BG256</Device><Speed></Speed></HardWare>
    <Source_Files>
        <Verilog>
            <File Path="../src/vendor/anlogic/apug011/include/global_def.v"><FileInfo><Attr Name="GlobalIncluded" Val="true"/><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="1"/></FileInfo></File>
            <File Path="../src/framebuf/async_fifo.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="2"/></FileInfo></File>
            <File Path="../src/storage/m1a_protocol.vh"><FileInfo><Attr Name="AutoExcluded" Val="true"/><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="3"/></FileInfo></File>
            <File Path="../src/storage/m1a_spi_slave.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="4"/></FileInfo></File>
            <File Path="../src/storage/m1a_command_decoder.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="5"/></FileInfo></File>
            <File Path="../src/storage/m1a_provider_cdc.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="6"/></FileInfo></File>
            <File Path="../src/storage/m1a_media_service_mock.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="7"/></FileInfo></File>
            <File Path="../src/storage/m1a_service_shell.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="8"/></FileInfo></File>
            <File Path="../src/storage/m1a_catalog_table.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="9"/></FileInfo></File>
            <File Path="../src/storage/fat32_scan.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="10"/></FileInfo></File>
            <File Path="../src/storage/m1a_fat32_catalog.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="11"/></FileInfo></File>
            <File Path="../src/storage/m1a_validation_top.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="12"/></FileInfo></File>
        </Verilog>
        <ADC_FILE></ADC_FILE>
        <SDC_FILE><File Path="M1A_timing.sdc"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="constraint_1"/><Attr Name="CompileOrder" Val="1"/></FileInfo></File></SDC_FILE>
    </Source_Files>
    <FileSets><FileSet Name="design_1" Type="DesignFiles"></FileSet><FileSet Name="constraint_1" Type="ConstrainFiles"></FileSet></FileSets>
    <TOP_MODULE><LABEL>m1a_validation_top</LABEL><MODULE>m1a_validation_top</MODULE><CREATEINDEX>user</CREATEINDEX></TOP_MODULE>
    <Property></Property><Device_Settings></Device_Settings><Configurations></Configurations>
    <Runs>
        <Run Name="syn_1" Type="Synthesis" ConstraintSet="constraint_1" Description="M1A standalone timing validation" Active="true"><Strategy Name="Default_Synthesis_Strategy"></Strategy><UserParams></UserParams></Run>
        <Run Name="phy_1" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="M1A standalone timing validation" SynRun="syn_1" Active="true"><Strategy Name="Default_PhysicalDesign_Strategy"></Strategy><UserParams></UserParams></Run>
    </Runs>
</Project>
