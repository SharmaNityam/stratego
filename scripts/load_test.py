"""Generate HTTP load against an explicitly supplied demo endpoint."""
import argparse
import time
from threading import Event
from concurrent.futures import ThreadPoolExecutor
from urllib.error import URLError
from urllib.request import urlopen


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('url', help='URL for your own test deployment, e.g. http://127.0.0.1:8080/')
    parser.add_argument('--seconds', type=int, default=120)
    parser.add_argument('--workers', type=int, default=20)
    args = parser.parse_args()
    if args.seconds <= 0 or args.workers <= 0:
        parser.error('seconds and workers must be positive')
    deadline = time.monotonic() + args.seconds
    stop = Event()

    def run_worker():
        successes = errors = 0
        while not stop.is_set() and time.monotonic() < deadline:
            try:
                with urlopen(args.url, timeout=5) as response:
                    response.read()
                successes += 1
            except (OSError, URLError):
                errors += 1
                time.sleep(0.1)
        return successes, errors

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        try:
            totals = list(pool.map(lambda _: run_worker(), range(args.workers)))
        except KeyboardInterrupt:
            stop.set()
            print('Stopping load test...')
            return
    print(f'Completed {sum(ok for ok, _ in totals)} requests; {sum(err for _, err in totals)} errors.')


if __name__ == '__main__':
    main()
