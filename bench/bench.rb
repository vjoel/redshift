def bench
  times = Process.times
  t0 = times.utime #+ times.stime

  yield

  times = Process.times
  t1 = times.utime #+ times.stime
  t1 - t0
end
