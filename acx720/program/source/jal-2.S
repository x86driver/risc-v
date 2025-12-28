_start:
    # Test 1: JAL with different register destinations
    addi x1, x0, 1          # x1 = 1 (marker)
    jal x1, test1_target     # Should overwrite x1 with return address
test1_return:
    addi x2, x0, 2          # x2 = 2 (marker, should execute)

    # Test 2: JAL to x0 (should discard return address)
    addi x3, x0, 3          # x3 = 3 (marker)
    jal x0, test2_target     # Return address discarded to x0
test2_return:
    addi x4, x0, 4          # x4 = 4 (marker, should execute)

    # Test 3: Nested JAL calls (test forwarding/hazard)
    addi x5, x0, 5          # x5 = 5 (marker)
    jal x6, nested_outer     # x6 = return address
test3_return:
    addi x7, x0, 7          # x7 = 7 (marker, should execute)

    # Test 4: JAL immediately after branch (pipeline hazard test)
    addi x8, x0, 10         # x8 = 10
    addi x9, x0, 10         # x9 = 10
    bne x8, x9, should_not_branch  # Should not branch (x8 == x9)
    jal x10, test4_target   # Should execute immediately after branch
test4_return:
    addi x11, x0, 11        # x11 = 11 (marker)

    # Test 5: JAL with maximum positive offset
    jal x12, far_target     # Test large positive jump
test5_return:
    addi x13, x0, 13        # x13 = 13 (marker)

    # Test 6: JAL with data dependency (forwarding test)
    addi x14, x0, 14        # x14 = 14
    add x15, x14, x0        # x15 = x14 (create dependency)
    jal x15, dep_target     # Should overwrite x15 with return address
test6_return:
    addi x16, x0, 16        # x16 = 16 (marker)

    # End program
    addi x31, x0, 999       # Final marker
    j end_program

# Test targets
test1_target:
    addi x17, x0, 17        # x17 = 17 (marker, should execute)
    j test1_return

test2_target:
    addi x18, x0, 18        # x18 = 18 (marker, should execute)  
    j test2_return

nested_outer:
    addi x19, x0, 19        # x19 = 19 (marker)
    jal x20, nested_inner   # Nested call
    addi x21, x0, 21        # x21 = 21 (should execute after inner returns)
    j test3_return

nested_inner:
    addi x22, x0, 22        # x22 = 22 (marker)
    j nested_outer + 8      # Return to nested_outer after jal

test4_target:
    addi x23, x0, 23        # x23 = 23 (marker)
    j test4_return

should_not_branch:
    addi x24, x0, 999       # x24 = 999 (ERROR: should not execute)
    j test4_return

dep_target:
    addi x25, x0, 25        # x25 = 25 (marker)
    j test6_return

far_target:
    addi x26, x0, 26        # x26 = 26 (marker)
    j test5_return

end_program:
    # Infinite loop to stop execution
    j end_program