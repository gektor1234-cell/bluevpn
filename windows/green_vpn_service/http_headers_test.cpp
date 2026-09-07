#include "http_headers.h"
#include <cassert>

int main() {
  using H = greenvpn::HttpHeaders;
  const std::string request = "POST /connect HTTP/1.1\r\nHost: localhost\r\nX-Local-Token: synthetic-test-only\r\n\r\n";
  for (std::size_t cut = 0; cut < request.size(); ++cut) {
    H headers;
    assert(headers.append(request.data(), cut) == H::State::incomplete);
    assert(headers.append(request.data() + cut, request.size() - cut) == H::State::complete);
    assert(headers.value() == request);
  }
  H individual;
  for (std::size_t index = 0; index < request.size(); ++index) {
    const auto expected = index + 1 == request.size() ? H::State::complete : H::State::incomplete;
    assert(individual.append(request.data() + index, 1) == expected);
  }
  H oversized;
  const std::string long_header(H::kMaxBytes + 1, 'a');
  assert(oversized.append(long_header.data(), long_header.size()) == H::State::too_large);
  H invalid;
  assert(invalid.append("\0", 1) == H::State::invalid);
}
