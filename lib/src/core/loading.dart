import 'dart:math' as math;

/// What the load watchdog concluded. [reason] is the word the Android SDK
/// reports in `onConnectivity`.
enum LoadVerdict {
  wait('wait'),
  stalled('stalled'),
  bootTimeout('boot_timeout'),
  loadCap('load_cap');

  const LoadVerdict(this.reason);
  final String reason;
}

/// WAITING IS NOT THE SAME AS BEING STUCK.
///
/// The engine page is downloaded over the customer's worst network. One flat
/// timer — "ready in 15 seconds or reload" — cancelled honest slow downloads,
/// threw away everything that had arrived, and started again; on a slow
/// enough link it could never finish. So the question is "is it still
/// moving?", with three limits for three different failures:
///
///   stall   nothing has arrived for a while — a dead socket, a captive portal
///   boot    everything arrived and the page still has not said ready — broken
///   cap     an overall ceiling, so a link that dribbles forever still ends
///
/// Time is an argument (milliseconds), so every rule is a plain test.
class LoadWatchdog {
  LoadWatchdog({this.stallMs = 15000, this.bootMs = 15000, this.hardCapMs = 120000});

  final int stallMs;
  final int bootMs;
  final int hardCapMs;

  int _startedAt = 0;
  int _movedAt = 0;
  int _progress = 0;
  bool _downloaded = false;

  void start(int now) {
    _startedAt = now;
    _movedAt = now;
    _progress = 0;
    _downloaded = false;
  }

  /// Progress 0–100 from the WebView. Monotonic: a lower report is not the
  /// page going backwards.
  void progress(int percent, int now) {
    if (percent <= _progress) return;
    _progress = percent;
    _movedAt = now;
    if (percent >= 100) _downloaded = true;
  }

  /// The page finished downloading; from here it is booting, not fetching.
  void loaded(int now) {
    _downloaded = true;
    _movedAt = now;
  }

  LoadVerdict check(int now) {
    final limit = _downloaded ? bootMs : stallMs;
    if (now - _movedAt >= limit) {
      return _downloaded ? LoadVerdict.bootTimeout : LoadVerdict.stalled;
    }
    if (now - _startedAt >= hardCapMs) return LoadVerdict.loadCap;
    return LoadVerdict.wait;
  }

  /// When to look again: the earlier of the two limits. Never busier than
  /// every 250ms, and never slower than a quarter of the window — a fixed
  /// floor swamps a short window the host asked for.
  int nextCheckInMs(int now) {
    final limit = _downloaded ? bootMs : stallMs;
    final untilLimit = limit - (now - _movedAt);
    final untilCap = hardCapMs - (now - _startedAt);
    final floor = math.min(250, limit ~/ 4);
    return math.max(floor, math.min(untilLimit, untilCap));
  }
}

/// How often to reload a page that failed, and when to stop.
///
/// Jittered ±25%: a thousand phones coming back from the same outage must not
/// reload the same page in the same second. Bounded: a phone with no network
/// stops and says so, rather than burning the battery in the background.
class RetryLadder {
  RetryLadder({
    List<int> delaysMs = const <int>[1000, 2000, 4000, 8000, 15000, 15000],
    double Function()? random,
  })  : _delaysMs = List<int>.unmodifiable(delaysMs),
        _random = random ?? math.Random().nextDouble;

  final List<int> _delaysMs;
  final double Function() _random;
  int _attempt = 0;

  /// Reloads scheduled so far.
  int get attempt => _attempt;

  bool get exhausted => _attempt >= _delaysMs.length;

  /// The delay before the next attempt, or null when every attempt is spent.
  int? next() {
    if (exhausted) return null;
    final base = _delaysMs[_attempt];
    _attempt++;
    return (base * (0.75 + _random() * 0.5)).round();
  }

  void reset() => _attempt = 0;
}
