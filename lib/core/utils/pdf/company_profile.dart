/// This business's own letterhead details, printed at the top of every
/// generated bill (quotation today; estimate/receipt would reuse this
/// too).
///
/// The values below match the sample quotation PDF exactly. There's no
/// company-profile API yet to sync these from — `login.php` only
/// returns [bill_prefix], not the rest of the letterhead — so this is a
/// static placeholder, same as the "NCW Fireworks Retail" text already
/// hardcoded elsewhere in the Quotation list. If a company-details
/// endpoint is added later, this is the one place to wire it up instead.
class CompanyProfile {
  static const name = 'NCW Fireworks Retail';
  static const addressLines = [
    '25, Mani Nagar',
    'Sivakasi - 626189',
    'Tamil Nadu',
  ];
  static const contactNumber = '1234567890';
  static const gstNumber = '22AAAAA0000A1Z5';
}