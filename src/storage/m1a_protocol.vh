`ifndef M1A_PROTOCOL_VH
`define M1A_PROTOCOL_VH

// M1A service-layer opcodes. These constants are transport-independent.
// The legacy SPI service shell may wrap them in its own frame, while the
// M1ABC board demo carries them inside db_ctrl_frame_*:
//   0x55, 0xA5, opcode, payload_length, payload[0..n-1], crc8(poly=0x07).
// Do not infer the physical transport from this header.
`define M1A_FRAME_SOF       8'hA5
`define M1A_CMD_OPEN        8'h01
`define M1A_CMD_NEXT        8'h02
`define M1A_CMD_PREV        8'h03
`define M1A_CMD_PLAY        8'h04
`define M1A_CMD_PAUSE       8'h05
`define M1A_CMD_SET_FORMAT  8'h06
`define M1A_CMD_CREDIT      8'h07
`define M1A_CMD_ABORT       8'h08
`define M1A_CMD_STATUS      8'h09

`define M1A_STATUS_READY    8'h01
`define M1A_STATUS_ACCEPTED 8'h02
`define M1A_STATUS_CREDIT   8'h03
`define M1A_STATUS_DONE     8'h04
`define M1A_STATUS_ERROR    8'hE0

`define M1A_ERR_BAD_FRAME   8'h01
`define M1A_ERR_BAD_CRC     8'h02
`define M1A_ERR_BAD_LENGTH  8'h03
`define M1A_ERR_BAD_IMAGE   8'h04
`define M1A_ERR_NOT_READY   8'h05

`define M1A_MEDIA_BMP       2'd1
`define M1A_FORMAT_RGB888   4'd1
`define M1A_CRC_INIT        16'hFFFF

`endif
