# need to allow combinatorial loops for ring oscillators (dont care about race conditions)
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical *ro0/chain*]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical *ro1/chain*]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical *ro2/chain*]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical *ro3/chain*]

# dont opt ring osc.
set_property DONT_TOUCH TRUE [get_cells -hierarchical *ring_osc*]