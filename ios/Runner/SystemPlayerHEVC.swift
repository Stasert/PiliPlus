import Foundation

/// Reads the colour transfer characteristics from an HEVC sequence parameter
/// set (VUI), as stored in an `hvcC` box.
///
/// AVPlayer checks the HLS `VIDEO-RANGE` against the bitstream and fails with
/// CoreMedia -12927 when they differ. Some bilibili HDR streams have no `colr`
/// box, so the SPS is the only place that says whether the video is PQ or HLG.
enum SystemPlayerHEVC {
  /// ITU-T H.273 transfer characteristics, e.g. 16 = PQ, 18 = HLG.
  static func transfer(hvcC b: [UInt8], body: Int, end: Int) -> Int? {
    // HEVCDecoderConfigurationRecord: 22 bytes, then the NAL unit arrays.
    var p = body + 22
    guard p < end else { return nil }
    let arrays = Int(b[p])
    p += 1
    for _ in 0..<arrays {
      guard p + 3 <= end else { return nil }
      let type = Int(b[p]) & 0x3f
      let count = Int(b[p + 1]) << 8 | Int(b[p + 2])
      p += 3
      for _ in 0..<count {
        guard p + 2 <= end else { return nil }
        let length = Int(b[p]) << 8 | Int(b[p + 1])
        p += 2
        guard p + length <= end else { return nil }
        if type == 33, let t = transfer(sps: Array(b[p..<(p + length)])) { return t }
        p += length
      }
    }
    return nil
  }

  /// `nal` includes the 2-byte NAL unit header.
  static func transfer(sps nal: [UInt8]) -> Int? {
    var r = BitReader(unescape(nal))
    r.skip(16)  // NAL unit header
    r.skip(4)  // sps_video_parameter_set_id
    let maxSubLayersMinus1 = r.u(3)
    r.skip(1)  // sps_temporal_id_nesting_flag
    profileTierLevel(&r, maxSubLayersMinus1)
    _ = r.ue()  // sps_seq_parameter_set_id
    if r.ue() == 3 { r.skip(1) }  // chroma_format_idc, separate_colour_plane_flag
    _ = r.ue()  // pic_width_in_luma_samples
    _ = r.ue()  // pic_height_in_luma_samples
    if r.u(1) == 1 { for _ in 0..<4 { _ = r.ue() } }  // conformance window
    _ = r.ue()  // bit_depth_luma_minus8
    _ = r.ue()  // bit_depth_chroma_minus8
    let log2MaxPocLsb = r.ue() + 4
    let orderingInfoForAll = r.u(1) == 1
    for _ in (orderingInfoForAll ? 0 : maxSubLayersMinus1)...maxSubLayersMinus1 {
      for _ in 0..<3 { _ = r.ue() }
    }
    for _ in 0..<6 { _ = r.ue() }  // block sizes, transform hierarchy depths
    if r.u(1) == 1, r.u(1) == 1 { scalingListData(&r) }
    r.skip(2)  // amp_enabled_flag, sample_adaptive_offset_enabled_flag
    if r.u(1) == 1 {  // pcm_enabled_flag
      r.skip(8)
      _ = r.ue()
      _ = r.ue()
      r.skip(1)
    }
    let numShortTermSets = r.ue()
    guard numShortTermSets <= 64 else { return nil }
    var numDeltaPocs = [Int]()
    for i in 0..<numShortTermSets {
      numDeltaPocs.append(shortTermRefPicSet(&r, i, numDeltaPocs))
    }
    if r.u(1) == 1 {  // long_term_ref_pics_present_flag
      let count = r.ue()
      guard count <= 32 else { return nil }
      for _ in 0..<count { r.skip(log2MaxPocLsb + 1) }
    }
    r.skip(2)  // sps_temporal_mvp_enabled_flag, strong_intra_smoothing_enabled_flag
    guard r.u(1) == 1 else { return nil }  // vui_parameters_present_flag
    if r.u(1) == 1, r.u(8) == 255 { r.skip(32) }  // aspect ratio
    if r.u(1) == 1 { r.skip(1) }  // overscan
    guard r.u(1) == 1 else { return nil }  // video_signal_type_present_flag
    r.skip(4)  // video_format, video_full_range_flag
    guard r.u(1) == 1 else { return nil }  // colour_description_present_flag
    r.skip(8)  // colour_primaries
    let transfer = r.u(8)
    return r.overrun ? nil : transfer
  }

  private static func profileTierLevel(_ r: inout BitReader, _ maxSubLayersMinus1: Int) {
    r.skip(96)  // general profile, flags and level
    var profilePresent = [Bool]()
    var levelPresent = [Bool]()
    for _ in 0..<maxSubLayersMinus1 {
      profilePresent.append(r.u(1) == 1)
      levelPresent.append(r.u(1) == 1)
    }
    if maxSubLayersMinus1 > 0 { r.skip(2 * (8 - maxSubLayersMinus1)) }
    for i in 0..<maxSubLayersMinus1 {
      if profilePresent[i] { r.skip(88) }
      if levelPresent[i] { r.skip(8) }
    }
  }

  private static func scalingListData(_ r: inout BitReader) {
    for sizeId in 0..<4 {
      for _ in stride(from: 0, to: 6, by: sizeId == 3 ? 3 : 1) {
        if r.u(1) == 0 {
          _ = r.ue()  // scaling_list_pred_matrix_id_delta
        } else {
          let coefficients = min(64, 1 << (4 + (sizeId << 1)))
          if sizeId > 1 { _ = r.ue() }  // scaling_list_dc_coef_minus8 (se)
          for _ in 0..<coefficients { _ = r.ue() }  // scaling_list_delta_coef (se)
        }
      }
    }
  }

  /// Returns NumDeltaPocs of this set.
  private static func shortTermRefPicSet(
    _ r: inout BitReader, _ index: Int, _ numDeltaPocs: [Int]
  ) -> Int {
    if index != 0, r.u(1) == 1 {  // inter_ref_pic_set_prediction_flag
      r.skip(1)  // delta_rps_sign
      _ = r.ue()  // abs_delta_rps_minus1
      var count = 0
      for _ in 0...numDeltaPocs[index - 1] {
        let used = r.u(1) == 1
        let useDelta = used || r.u(1) == 1
        if useDelta { count += 1 }
      }
      return count
    }
    let negative = r.ue()
    let positive = r.ue()
    guard negative + positive <= 32 else { return 0 }
    for _ in 0..<(negative + positive) {
      _ = r.ue()
      r.skip(1)
    }
    return negative + positive
  }

  /// Removes emulation prevention bytes (00 00 03 -> 00 00).
  private static func unescape(_ data: [UInt8]) -> [UInt8] {
    var out = [UInt8]()
    out.reserveCapacity(data.count)
    var zeros = 0
    for byte in data {
      if zeros >= 2 && byte == 3 {
        zeros = 0
        continue
      }
      out.append(byte)
      zeros = byte == 0 ? zeros + 1 : 0
    }
    return out
  }
}

private struct BitReader {
  private let data: [UInt8]
  private var position = 0
  private(set) var overrun = false

  init(_ data: [UInt8]) { self.data = data }

  mutating func u(_ count: Int) -> Int {
    var value = 0
    for _ in 0..<count {
      let byte = position >> 3
      guard byte < data.count else {
        overrun = true
        return 0
      }
      value = value << 1 | Int(data[byte] >> (7 - UInt8(position & 7)) & 1)
      position += 1
    }
    return value
  }

  mutating func skip(_ count: Int) { position += count }

  /// Exp-Golomb; signed values are read the same way since only skipped.
  mutating func ue() -> Int {
    var leadingZeros = 0
    while u(1) == 0 {
      leadingZeros += 1
      if leadingZeros > 31 || overrun { return 0 }
    }
    return (1 << leadingZeros) - 1 + u(leadingZeros)
  }
}
