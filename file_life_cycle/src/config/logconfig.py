# -*- coding: utf-8 -*-
import os
import logging
from logging.config import dictConfig


FILE_LIFE_CYCLE_DIR = '/var/log/file_life_cycle/'

if not os.path.exists(FILE_LIFE_CYCLE_DIR):
    os.mkdir(FILE_LIFE_CYCLE_DIR)

LOGGING_CONFIG = dict(
    version=1,
    formatters={
        'f': {
            'format': '%(asctime)s %(levelname)s %(pathname)s %(funcName)s %(lineno)d %(thread)d %(message)s'
        }
    },
    handlers={
        'notifier':{
            'filename': FILE_LIFE_CYCLE_DIR + 'notifier.log',
            'class': 'logging.handlers.TimedRotatingFileHandler',
            'formatter': 'f',
            'when': 'midnight',
            'backupCount': 7
        },
    },
    loggers={
        'Notifier':{
            'handlers': ['notifier'],
            'level': 'WARNING',
        },
    },
)

dictConfig(LOGGING_CONFIG)

notifier_logger = logging.getLogger('Notifier')
