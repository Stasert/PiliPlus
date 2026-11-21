import Foundation

/// Reads the colour description from the AV1 sequence header stored in an
/// `av1C` box (its configOBUs).
///
/// AVPlayer checks the HLS `VIDEO-RANGE` against the bitstream (see
/// SystemPlayerHEVC for HEVC). An AV1 track may have no `colr` box, so the
/// sequence header is then the only place that says whether it is PQ or HLG.
enum SystemPlayerAV1 {
  struct Colour {
    /// color_description_present_flag. Without it the three codes below are
    /// 2 (unspecified).
    let described: Bool
    /// ITU-T H.273 codes, as in the AV1 color_config (2 = unspecified).
    let primaries: Int
    let transfer: Int
    let matrix: Int
    /// color_range: 1 = full range.
    let fullRange: Int
  }

  /// `body` is the start of the av1C payload: a 4-byte header, then OBUs.
  static func colour(av1C b: [UInt8], body: Int, end: Int) -> Colour? {
    var p = body + 4
    while p < end {
      let header = b[p]
      let type = Int(header >> 3) & 0xF
      let hasExtension = header & 0x04 != 0
      let hasSize = header & 0x02 != 0
      p += hasExtension ? 2 : 1
      guard p <= end else { return nil }
      var size = end - p
      if hasSize {
        guard let (value, length) = leb128(b, p, end) else { return nil }
        p += length
        size = value
      }
      guard size <= end - p else { return nil }
      if type == 1 {  // OBU_SEQUENCE_HEADER
        return colour(sequenceHeader: Array(b[p..<(p + size)]))
      }
      p += size
    }
    return nil
  }

  /// Unsigned LEB128 (at most 8 bytes, as AV1 allows). Returns the value and
  /// its length in bytes.
  private static func leb128(_ b: [UInt8], _ start: Int, _ end: Int) -> (Int, Int)? {
    var value = 0
    for i in 0..<8 {
      guard start + i < end else { return nil }
      let byte = Int(b[start + i])
      value |= (byte & 0x7F) << (i * 7)
      if byte & 0x80 == 0 { return (value, i + 1) }
    }
    return nil
  }

  /// Walks sequence_header_obu() (AV1 spec 5.5) up to color_config().
  static func colour(sequenceHeader data: [UInt8]) -> Colour? {
    var r = SystemPlayerBitReader(data)
    let profile = r.u(3)
    r.skip(1)  // still_picture
    let reduced = r.u(1) == 1  // reduced_still_picture_header
    if reduced {
      r.skip(5)  // seq_level_idx[0]
    } else {
      var decoderModelInfo = false
      var bufferDelayLength = 0
      if r.u(1) == 1 {  // timing_info_present_flag
        r.skip(64)  // num_units_in_display_tick, time_scale
        if r.u(1) == 1 { uvlc(&r) }  // equal_picture_interval, num_ticks_per_picture_minus_1
        decoderModelInfo = r.u(1) == 1
        if decoderModelInfo {
          bufferDelayLength = r.u(5) + 1
          r.skip(32)  // num_units_in_decoding_tick
          r.skip(10)  // buffer_removal_time_length_minus_1, frame_presentation_time_length_minus_1
        }
      }
      let initialDisplayDelay = r.u(1) == 1
      let operatingPoints = r.u(5) + 1
      for _ in 0..<operatingPoints {
        r.skip(12)  // operating_point_idc
        if r.u(5) > 7 { r.skip(1) }  // seq_level_idx, seq_tier
        if decoderModelInfo, r.u(1) == 1 {  // decoder_model_present_for_this_op
          r.skip(2 * bufferDelayLength + 1)  // buffer delays, low_delay_mode_flag
        }
        if initialDisplayDelay, r.u(1) == 1 { r.skip(4) }  // initial_display_delay_minus_1
      }
    }
    let widthBits = r.u(4) + 1
    let heightBits = r.u(4) + 1
    r.skip(widthBits + heightBits)  // max_frame_width_minus_1, max_frame_height_minus_1
    if !reduced, r.u(1) == 1 { r.skip(7) }  // frame_id_numbers_present_flag, id lengths
    r.skip(3)  // use_128x128_superblock, enable_filter_intra, enable_intra_edge_filter
    if !reduced {
      r.skip(4)  // interintra / masked compound, warped motion, dual filter
      let orderHint = r.u(1) == 1  // enable_order_hint
      if orderHint { r.skip(2) }  // enable_jnt_comp, enable_ref_frame_mvs
      // seq_choose_screen_content_tools, else seq_force_screen_content_tools
      let screenContent = r.u(1) == 1 ? 2 : r.u(1)
      // seq_choose_integer_mv, else seq_force_integer_mv
      if screenContent > 0, r.u(1) == 0 { r.skip(1) }
      if orderHint { r.skip(3) }  // order_hint_bits_minus_1
    }
    r.skip(3)  // enable_superres, enable_cdef, enable_restoration
    // color_config()
    let highBitdepth = r.u(1) == 1
    if profile == 2, highBitdepth { r.skip(1) }  // twelve_bit
    let monochrome = profile == 1 ? false : r.u(1) == 1
    var primaries = 2
    var transfer = 2
    var matrix = 2
    let described = r.u(1) == 1  // color_description_present_flag
    if described {
      primaries = r.u(8)
      transfer = r.u(8)
      matrix = r.u(8)
    }
    // sRGB (BT.709 primaries, sRGB transfer, identity matrix) implies full
    // range without a color_range bit.
    let fullRange =
      !monochrome && primaries == 1 && transfer == 13 && matrix == 0 ? 1 : r.u(1)
    guard !r.overrun else { return nil }
    return Colour(
      described: described, primaries: primaries, transfer: transfer, matrix: matrix,
      fullRange: fullRange)
  }

  /// uvlc() (AV1 spec 4.10.3); the value is only skipped.
  private static func uvlc(_ r: inout SystemPlayerBitReader) {
    var leadingZeros = 0
    while r.u(1) == 0 {
      leadingZeros += 1
      if leadingZeros >= 32 || r.overrun { return }
    }
    r.skip(leadingZeros)
  }
}
