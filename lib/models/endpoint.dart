/// An available backend endpoint.
class Endpoint {
  final String label;
  final String url;
  const Endpoint(this.label, this.url);
}

/// Preset endpoints offered in the selector.
const List<Endpoint> kPresetEndpoints = [
  Endpoint('岭南师范学院', 'http://jw.lingnan.edu.cn'),
  Endpoint('岭南师范学院IPV4', 'http://202.192.143.203'),
  Endpoint('岭南师范学院HTTPS', 'https://jw.lingnan.edu.cn'),
  Endpoint('广州商学院', 'http://jwxt.gcc.edu.cn'),
  Endpoint('广州商学院HTTPS', 'https://jwxt.gcc.edu.cn'),
];
