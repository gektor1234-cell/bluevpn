#pragma once

#include <cstddef>
#include <string>

namespace greenvpn {
class HttpHeaders {
 public:
  static constexpr std::size_t kMaxBytes = 16384;
  enum class State { incomplete, complete, invalid, too_large };

  State append(const char* bytes, std::size_t count) {
    if (state_ != State::incomplete) return state_;
    for (std::size_t index = 0; index < count; ++index) {
      const auto ch = static_cast<unsigned char>(bytes[index]);
      if (ch == 0 || (ch < 32 && ch != '\r' && ch != '\n' && ch != '\t')) {
        return state_ = State::invalid;
      }
      if (headers_.size() == kMaxBytes) return state_ = State::too_large;
      headers_ += static_cast<char>(ch);
      if (headers_.size() >= 4 && headers_.compare(headers_.size() - 4, 4, "\r\n\r\n") == 0) {
        return state_ = State::complete;
      }
    }
    return state_;
  }
  const std::string& value() const { return headers_; }
 private:
  State state_ = State::incomplete;
  std::string headers_;
};
}  // namespace greenvpn
