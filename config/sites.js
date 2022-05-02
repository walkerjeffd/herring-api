module.exports = {
  default: {
    window: {
      start_date: '2021-04-01',
      end_date: '2021-07-01',
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
      start_date: '2021-04-01',
      end_date: '2021-07-01'
    },
    allVideos: {
      start_date: '2021-04-01',
      end_date: '2021-07-01'
    },
    run: {
      start_date: '2021-04-01',
      end_date: '2021-07-01'
    }
  },
  UML: {
    window: {
      start_date: '2022-04-24',
      end_date: '2022-06-15',
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
      // distribution: 'exponential',
      // lambda: 0.0005
      distribution: 'uniform'
    },
    status: {
      start_date: '2022-04-24',
      end_date: '2022-06-15'
    },
    run: {
      start_date: '2022-04-24',
      end_date: '2022-06-15'
    },
    leaderboard: {
      start_date: '2022-01-01',
      end_date: '2022-12-31'
    }
  },
  PLY: {
    window: {
      start_date: '2022-04-19',
      end_date: '2022-07-01',
      method: 'fixed'
    },
    sampler: {
      distribution: 'uniform'
      // distribution: 'exponential',
      // lambda: 0.0005
    },
    counts: {
      min_count_n: 0,
      max_count_n: 2,
      min_count_mean: 0
    },
    status: {
      start_date: '2022-04-19',
      end_date: '2022-07-01'
    },
    run: {
      start_date: '2022-04-19',
      end_date: '2022-07-01'
    }
  },
  NSRWA: {
    window: {
      start_date: '2022-04-01',
      end_date: '2022-07-01',
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
      start_date: '2022-04-15',
      end_date: '2022-07-01'
    },
    run: {
      start_date: '2022-04-15',
      end_date: '2022-07-01'
    }
  }
}
