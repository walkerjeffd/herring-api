module.exports = {
  default: {
    window: {
      start_date: '2022-04-01',
      end_date: '2022-07-01',
      method: 'fixed'
    },
    times: {
      start_hour: 7,
      end_hour: 18
    },
    counts: {
      min_count_n: 0,
      max_count_n: 1000,
      min_count_mean: 0
    },
    sampler: {
      distribution: 'uniform'
    },
    status: {
      start_date: '2022-04-01',
      end_date: '2022-07-01'
    },
    allVideos: {
      start_date: '2022-04-01',
      end_date: '2022-07-01'
    },
    run: {
      start_date: '2022-04-01',
      end_date: '2022-07-01'
    }
  },
  UML: {
    window: {
      start_date: '2025-04-01',
      end_date: '2025-07-01',
      method: 'fixed'
    },
    times: {
      start_hour: 7,
      end_hour: 18
    },
    counts: {
      min_count_n: 0,
      max_count_n: 2,
      min_count_mean: 0
    },
    sampler: {
      distribution: 'exponential',
      lambda: 0.0005
      // distribution: 'uniform'
    },
    status: {
      start_date: '2025-04-30',
      end_date: '2025-07-01'
    },
    run: {
      start_date: '2025-04-30',
      end_date: '2025-07-01'
    },
    leaderboard: {
      start_date: '2025-01-01',
      end_date: '2025-12-31'
    }
  },
  PLY: {
    window: {
      start_date: '2025-04-15',
      end_date: '2025-07-01',
      method: 'fixed'
    },
    times: {
      start_hour: 0,
      end_hour: 24
    },
    sampler: {
      //distribution: 'uniform'
      distribution: 'exponential',
      lambda: 0.0005
    },
    counts: {
      min_count_n: 0,
      max_count_n: 2,
      min_count_mean: 0
    },
    status: {
      start_date: '2025-04-15',
      end_date: '2025-07-01'
    },
    run: {
      start_date: '2025-04-15',
      end_date: '2025-07-01',
      fullDay: true
    }
  },
  NSRWA: {
    window: {
      start_date: '2022-04-25',
      end_date: '2022-05-23',
      method: 'fixed'
    },
    sampler: {
      distribution: 'uniform'
    },
    counts: {
      min_count_n: 0,
      max_count_n: 2,
      min_count_mean: 0
    },
    status: {
      start_date: '2022-04-25',
      end_date: '2022-05-23'
    },
    run: {
      start_date: '2022-04-25',
      end_date: '2022-05-23'
    }
  },
  PEN: {
    window: {
      start_date: '2023-05-08',
      end_date: '2023-06-20',
      method: 'fixed'
    },
    times: {
      start_hour: 7,
      end_hour: 18
    },
    counts: {
      min_count_n: 0,
      max_count_n: 2,
      min_count_mean: 0
    },
    sampler: {
      //distribution: 'exponential',
      //lambda: 0.0005
      distribution: 'uniform'
    },
    status: {
      start_date: '2023-05-08',
      end_date: '2023-06-20'
    },
    run: {
      start_date: '2023-05-08',
      end_date: '2023-07-20'
    },
    leaderboard: {
      start_date: '2023-01-01',
      end_date: '2023-12-31'
    }
  }
}
