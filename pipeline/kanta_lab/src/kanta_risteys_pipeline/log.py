import logging
from os import getenv


class ColoredFormatter(logging.Formatter):
    def format(self, record):
        red = 31
        yellow = 33
        blue = 34
        white = 37
        gray = 90

        def in_color(text, ansi_code):
            """Color the log level using ANSI codes"""
            return f"\033[1;{ansi_code}m{text}\033[0m"

        if record.levelno == logging.CRITICAL:
            log_level = in_color("CRIT ", red)
        elif record.levelno == logging.ERROR:
            log_level = in_color("ERROR", red)
        elif record.levelno == logging.WARNING:
            log_level = in_color("WARN ", yellow)
        elif record.levelno == logging.INFO:
            log_level = in_color("INFO ", blue)
        elif record.levelno == logging.DEBUG:
            log_level = in_color("DEBUG", white)

        when = in_color("%(asctime)s", gray)
        where = in_color("%(module)s:%(funcName)s:%(lineno)d", gray)
        fmt = f"{when} {log_level} --  %(message)s    {where}"
        formatter = logging.Formatter(fmt)
        return formatter.format(record)


logger = logging.getLogger(__name__)

level = getenv("LOG_LEVEL", logging.INFO)
logger.setLevel(level)

stream_handler = logging.StreamHandler()
stream_handler.setFormatter(ColoredFormatter())
logger.addHandler(stream_handler)
