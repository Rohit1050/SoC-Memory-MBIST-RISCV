#  Copyright 2019-2026 Western Digital Corporation or its affiliates.
#  Copyright 2022-2026 Antmicro <www.antmicro.com>
# 
#  SPDX-License-Identifier: Apache-2.0
#  Licensed under the Apache License, Version 2.0, see LICENSE for details.
# 
#  This is an automatically generated file by student on Sat Oct 10 15:39:36 IST 2026
# 
#  cmd:    veer -target=default -set build_axi4 
# 
# To use this in a perf script, use 'require $RV_ROOT/configs/config.pl'
# Reference the hash via $config{name}..


%config = (
            'xlen' => 32,
            'pic' => {
                       'pic_meipt_count' => 31,
                       'pic_mpiccfg_offset' => '0x3000',
                       'pic_meie_count' => 31,
                       'pic_meipl_offset' => '0x0000',
                       'pic_meip_mask' => '0x0',
                       'pic_bits' => 15,
                       'pic_total_int_plus1' => 32,
                       'pic_meigwctrl_offset' => '0x4000',
                       'pic_size' => 32,
                       'pic_meigwctrl_count' => 31,
                       'pic_meip_offset' => '0x1000',
                       'pic_meipt_mask' => '0x0',
                       'pic_meipl_mask' => '0xf',
                       'pic_mpiccfg_mask' => '0x1',
                       'pic_meip_count' => 1,
                       'pic_region' => '0xf',
                       'pic_int_words' => 1,
                       'pic_meigwclr_offset' => '0x5000',
                       'pic_total_int' => 31,
                       'pic_offset' => '0xc0000',
                       'pic_meie_offset' => '0x2000',
                       'pic_meigwctrl_mask' => '0x3',
                       'pic_meipt_offset' => '0x3004',
                       'pic_meigwclr_count' => 31,
                       'pic_meie_mask' => '0x1',
                       'pic_mpiccfg_count' => 1,
                       'pic_meipl_count' => 31,
                       'pic_base_addr' => '0xf00c0000',
                       'pic_meigwclr_mask' => '0x0'
                     },
            'csr' => {
                       'mfdhs' => {
                                    'reset' => '0x0',
                                    'exists' => 'true',
                                    'mask' => '0x00000003',
                                    'number' => '0x7cf',
                                    'comment' => 'Force Debug Halt Status'
                                  },
                       'dicawics' => {
                                       'comment' => 'Cache diagnostics.',
                                       'number' => '0x7c8',
                                       'mask' => '0x0130fffc',
                                       'reset' => '0x0',
                                       'exists' => 'true',
                                       'debug' => 'true'
                                     },
                       'mhpmevent6' => {
                                         'mask' => '0xffffffff',
                                         'exists' => 'true',
                                         'reset' => '0x0'
                                       },
                       'mhpmcounter5' => {
                                           'reset' => '0x0',
                                           'exists' => 'true',
                                           'mask' => '0xffffffff'
                                         },
                       'mhpmcounter3h' => {
                                            'mask' => '0xffffffff',
                                            'exists' => 'true',
                                            'reset' => '0x0'
                                          },
                       'dicago' => {
                                     'comment' => 'Cache diagnostics.',
                                     'number' => '0x7cb',
                                     'debug' => 'true',
                                     'mask' => '0x0',
                                     'exists' => 'true',
                                     'reset' => '0x0'
                                   },
                       'mstatus' => {
                                      'exists' => 'true',
                                      'reset' => '0x1800',
                                      'mask' => '0x88'
                                    },
                       'meicidpl' => {
                                       'number' => '0xbcb',
                                       'comment' => 'External interrupt claim id priority level.',
                                       'mask' => '0xf',
                                       'exists' => 'true',
                                       'reset' => '0x0'
                                     },
                       'mhpmcounter5h' => {
                                            'exists' => 'true',
                                            'reset' => '0x0',
                                            'mask' => '0xffffffff'
                                          },
                       'mitctl1' => {
                                      'mask' => '0x0000000f',
                                      'exists' => 'true',
                                      'reset' => '0x1',
                                      'number' => '0x7d7'
                                    },
                       'mdccmect' => {
                                       'reset' => '0x0',
                                       'exists' => 'true',
                                       'mask' => '0xffffffff',
                                       'number' => '0x7f2'
                                     },
                       'mhpmcounter4' => {
                                           'mask' => '0xffffffff',
                                           'exists' => 'true',
                                           'reset' => '0x0'
                                         },
                       'mhpmevent5' => {
                                         'mask' => '0xffffffff',
                                         'reset' => '0x0',
                                         'exists' => 'true'
                                       },
                       'instret' => {
                                      'exists' => 'false'
                                    },
                       'miccmect' => {
                                       'mask' => '0xffffffff',
                                       'exists' => 'true',
                                       'reset' => '0x0',
                                       'number' => '0x7f1'
                                     },
                       'mcpc' => {
                                   'mask' => '0x0',
                                   'exists' => 'true',
                                   'reset' => '0x0',
                                   'number' => '0x7c2',
                                   'comment' => 'Core pause'
                                 },
                       'mhpmevent4' => {
                                         'mask' => '0xffffffff',
                                         'reset' => '0x0',
                                         'exists' => 'true'
                                       },
                       'mitctl0' => {
                                      'number' => '0x7d4',
                                      'reset' => '0x1',
                                      'exists' => 'true',
                                      'mask' => '0x00000007'
                                    },
                       'cycle' => {
                                    'exists' => 'false'
                                  },
                       'time' => {
                                   'exists' => 'false'
                                 },
                       'mhpmcounter4h' => {
                                            'reset' => '0x0',
                                            'exists' => 'true',
                                            'mask' => '0xffffffff'
                                          },
                       'dicad1' => {
                                     'number' => '0x7ca',
                                     'comment' => 'Cache diagnostics.',
                                     'debug' => 'true',
                                     'mask' => '0x3',
                                     'exists' => 'true',
                                     'reset' => '0x0'
                                   },
                       'mpmc' => {
                                   'number' => '0x7c6',
                                   'mask' => '0x2',
                                   'exists' => 'true',
                                   'reset' => '0x2'
                                 },
                       'mitbnd1' => {
                                      'mask' => '0xffffffff',
                                      'exists' => 'true',
                                      'reset' => '0xffffffff',
                                      'number' => '0x7d6'
                                    },
                       'mhpmcounter6' => {
                                           'mask' => '0xffffffff',
                                           'reset' => '0x0',
                                           'exists' => 'true'
                                         },
                       'mrac' => {
                                   'mask' => '0xffffffff',
                                   'exists' => 'true',
                                   'reset' => '0x0',
                                   'shared' => 'true',
                                   'number' => '0x7c0',
                                   'comment' => 'Memory region io and cache control.'
                                 },
                       'mhpmcounter3' => {
                                           'reset' => '0x0',
                                           'exists' => 'true',
                                           'mask' => '0xffffffff'
                                         },
                       'mfdc' => {
                                   'number' => '0x7f9',
                                   'mask' => '0x00071fff',
                                   'exists' => 'true',
                                   'reset' => '0x00070040'
                                 },
                       'mitbnd0' => {
                                      'number' => '0x7d3',
                                      'reset' => '0xffffffff',
                                      'exists' => 'true',
                                      'mask' => '0xffffffff'
                                    },
                       'dicad0' => {
                                     'mask' => '0xffffffff',
                                     'exists' => 'true',
                                     'reset' => '0x0',
                                     'debug' => 'true',
                                     'number' => '0x7c9',
                                     'comment' => 'Cache diagnostics.'
                                   },
                       'mip' => {
                                  'mask' => '0x0',
                                  'exists' => 'true',
                                  'reset' => '0x0',
                                  'poke_mask' => '0x70000888'
                                },
                       'mfdht' => {
                                    'mask' => '0x0000003f',
                                    'exists' => 'true',
                                    'reset' => '0x0',
                                    'shared' => 'true',
                                    'number' => '0x7ce',
                                    'comment' => 'Force Debug Halt Threshold'
                                  },
                       'mhartid' => {
                                      'mask' => '0x0',
                                      'poke_mask' => '0xfffffff0',
                                      'exists' => 'true',
                                      'reset' => '0x0'
                                    },
                       'dmst' => {
                                   'comment' => 'Memory synch trigger: Flush caches in debug mode.',
                                   'number' => '0x7c4',
                                   'reset' => '0x0',
                                   'exists' => 'true',
                                   'mask' => '0x0',
                                   'debug' => 'true'
                                 },
                       'mitcnt1' => {
                                      'number' => '0x7d5',
                                      'reset' => '0x0',
                                      'exists' => 'true',
                                      'mask' => '0xffffffff'
                                    },
                       'mimpid' => {
                                     'mask' => '0x0',
                                     'exists' => 'true',
                                     'reset' => '0x4'
                                   },
                       'tselect' => {
                                      'reset' => '0x0',
                                      'exists' => 'true',
                                      'mask' => '0x3'
                                    },
                       'misa' => {
                                   'mask' => '0x0',
                                   'exists' => 'true',
                                   'reset' => '0x40001104'
                                 },
                       'meicurpl' => {
                                       'mask' => '0xf',
                                       'reset' => '0x0',
                                       'exists' => 'true',
                                       'number' => '0xbcc',
                                       'comment' => 'External interrupt current priority level.'
                                     },
                       'dcsr' => {
                                   'mask' => '0x00008c04',
                                   'poke_mask' => '0x00008dcc',
                                   'exists' => 'true',
                                   'reset' => '0x40000003',
                                   'debug' => 'true'
                                 },
                       'mcgc' => {
                                   'mask' => '0x000003ff',
                                   'exists' => 'true',
                                   'reset' => '0x200',
                                   'poke_mask' => '0x000003ff',
                                   'number' => '0x7f8'
                                 },
                       'mcountinhibit' => {
                                            'poke_mask' => '0x7d',
                                            'exists' => 'true',
                                            'reset' => '0x0',
                                            'commnet' => 'Performance counter inhibit. One bit per counter.',
                                            'mask' => '0x7d'
                                          },
                       'mhpmevent3' => {
                                         'reset' => '0x0',
                                         'exists' => 'true',
                                         'mask' => '0xffffffff'
                                       },
                       'mie' => {
                                  'exists' => 'true',
                                  'reset' => '0x0',
                                  'mask' => '0x70000888'
                                },
                       'mvendorid' => {
                                        'mask' => '0x0',
                                        'reset' => '0x45',
                                        'exists' => 'true'
                                      },
                       'marchid' => {
                                      'mask' => '0x0',
                                      'exists' => 'true',
                                      'reset' => '0x00000010'
                                    },
                       'meipt' => {
                                    'mask' => '0xf',
                                    'exists' => 'true',
                                    'reset' => '0x0',
                                    'number' => '0xbc9',
                                    'comment' => 'External interrupt priority threshold.'
                                  },
                       'mscause' => {
                                      'number' => '0x7ff',
                                      'reset' => '0x0',
                                      'exists' => 'true',
                                      'mask' => '0x0000000f'
                                    },
                       'mcounteren' => {
                                         'exists' => 'false'
                                       },
                       'mhpmcounter6h' => {
                                            'reset' => '0x0',
                                            'exists' => 'true',
                                            'mask' => '0xffffffff'
                                          },
                       'mitcnt0' => {
                                      'number' => '0x7d2',
                                      'reset' => '0x0',
                                      'exists' => 'true',
                                      'mask' => '0xffffffff'
                                    },
                       'micect' => {
                                     'number' => '0x7f0',
                                     'mask' => '0xffffffff',
                                     'reset' => '0x0',
                                     'exists' => 'true'
                                   }
                     },
            'physical' => '1',
            'num_mmode_perf_regs' => '4',
            'triggers' => [
                            {
                              'poke_mask' => [
                                               '0x081818c7',
                                               '0xffffffff',
                                               '0x00000000'
                                             ],
                              'reset' => [
                                           '0x23e00000',
                                           '0x00000000',
                                           '0x00000000'
                                         ],
                              'mask' => [
                                          '0x081818c7',
                                          '0xffffffff',
                                          '0x00000000'
                                        ]
                            },
                            {
                              'mask' => [
                                          '0x081810c7',
                                          '0xffffffff',
                                          '0x00000000'
                                        ],
                              'poke_mask' => [
                                               '0x081810c7',
                                               '0xffffffff',
                                               '0x00000000'
                                             ],
                              'reset' => [
                                           '0x23e00000',
                                           '0x00000000',
                                           '0x00000000'
                                         ]
                            },
                            {
                              'mask' => [
                                          '0x081818c7',
                                          '0xffffffff',
                                          '0x00000000'
                                        ],
                              'reset' => [
                                           '0x23e00000',
                                           '0x00000000',
                                           '0x00000000'
                                         ],
                              'poke_mask' => [
                                               '0x081818c7',
                                               '0xffffffff',
                                               '0x00000000'
                                             ]
                            },
                            {
                              'mask' => [
                                          '0x081810c7',
                                          '0xffffffff',
                                          '0x00000000'
                                        ],
                              'poke_mask' => [
                                               '0x081810c7',
                                               '0xffffffff',
                                               '0x00000000'
                                             ],
                              'reset' => [
                                           '0x23e00000',
                                           '0x00000000',
                                           '0x00000000'
                                         ]
                            }
                          ],
            'btb' => {
                       'btb_index1_lo' => '2',
                       'btb_toffset_size' => '12',
                       'btb_index3_lo' => 18,
                       'btb_addr_lo' => '2',
                       'btb_btag_size' => 5,
                       'btb_size' => 512,
                       'btb_array_depth' => 256,
                       'btb_index2_hi' => 17,
                       'btb_enable' => '1',
                       'btb_index2_lo' => 10,
                       'btb_addr_hi' => 9,
                       'btb_index3_hi' => 25,
                       'btb_index1_hi' => 9,
                       'btb_btag_fold' => 0,
                       'btb_fold2_index_hash' => 0
                     },
            'max_mmode_perf_event' => '516',
            'even_odd_trigger_chains' => 'true',
            'regwidth' => '32',
            'config_key' => '32\'hdeadbeef',
            'icache' => {
                          'icache_tag_num_bypass_width' => 2,
                          'icache_index_hi' => 12,
                          'icache_beat_addr_hi' => 5,
                          'icache_bank_width' => 8,
                          'icache_bank_lo' => 3,
                          'icache_tag_num_bypass' => '2',
                          'icache_beat_bits' => 3,
                          'icache_bank_hi' => 3,
                          'icache_enable' => 1,
                          'icache_bypass_enable' => '1',
                          'icache_waypack' => '1',
                          'icache_scnd_last' => 6,
                          'icache_banks_way' => 2,
                          'icache_size' => 16,
                          'icache_num_bypass_width' => 2,
                          'icache_num_lines_bank' => '64',
                          'icache_data_index_lo' => 4,
                          'icache_bank_bits' => 1,
                          'icache_data_depth' => '512',
                          'icache_num_bypass' => '2',
                          'icache_2banks' => '1',
                          'icache_tag_bypass_enable' => '1',
                          'icache_tag_depth' => 128,
                          'icache_num_lines' => 256,
                          'icache_tag_index_lo' => '6',
                          'icache_num_lines_way' => '128',
                          'icache_num_beats' => 8,
                          'icache_data_width' => 64,
                          'icache_num_ways' => 2,
                          'icache_tag_cell' => 'ram_128x25',
                          'icache_status_bits' => 1,
                          'icache_ecc' => '1',
                          'icache_fdata_width' => 71,
                          'icache_ln_sz' => 64,
                          'icache_tag_lo' => 13,
                          'icache_data_cell' => 'ram_512x71'
                        },
            'user_ec_rv_icg' => 'user_clock_gate',
            'numiregs' => '32',
            'tec_rv_icg' => 'clockhdr',
            'core' => {
                        'iccm_icache' => 1,
                        'timer_legal_en' => '1',
                        'icache_only' => 'derived',
                        'lsu_stbuf_depth' => '4',
                        'bitmanip_zbc' => 1,
                        'bitmanip_zbb' => 1,
                        'no_iccm_no_icache' => 'derived',
                        'bitmanip_zbs' => 1,
                        'bitmanip_zbf' => 0,
                        'div_new' => 1,
                        'lsu_num_nbload' => '4',
                        'lsu_num_nbload_width' => '2',
                        'div_bit' => '4',
                        'bitmanip_zbp' => 0,
                        'bitmanip_zbe' => 0,
                        'bitmanip_zba' => 1,
                        'dma_buf_depth' => '5',
                        'lsu2dma' => 0,
                        'fpga_optimize' => 1,
                        'iccm_only' => 'derived',
                        'fast_interrupt_redirect' => '1',
                        'bitmanip_zbr' => 0
                      },
            'harts' => 1,
            'nmi_vec' => '0x11110000',
            'reset_vec' => '0x80000000',
            'memmap' => {
                          'external_data_1' => '0xb0000000',
                          'unused_region4' => '0x40000000',
                          'unused_region0' => '0x90000000',
                          'external_data' => '0xc0580000',
                          'unused_region3' => '0x50000000',
                          'serialio' => '0xd0580000',
                          'consoleio' => '0xd0580000',
                          'unused_region8' => '0x00000000',
                          'unused_region2' => '0x60000000',
                          'unused_region6' => '0x20000000',
                          'unused_region5' => '0x30000000',
                          'unused_region1' => '0x70000000',
                          'debug_sb_mem' => '0xa0580000',
                          'unused_region7' => '0x10000000'
                        },
            'testbench' => {
                             'build_axi4' => 1,
                             'sterr_rollback' => '0',
                             'RV_TOP' => '`TOP.rvtop_wrapper.rvtop',
                             'CPU_TOP' => '`RV_TOP.veer',
                             'build_axi_native' => 1,
                             'TOP' => 'tb_top',
                             'SDVT_AHB' => 0,
                             'lderr_rollback' => '1',
                             'ext_datawidth' => '64',
                             'clock_period' => '100',
                             'ext_addrwidth' => '32'
                           },
            'retstack' => {
                            'ret_stack_size' => '8'
                          },
            'bht' => {
                       'bht_ghr_size' => 8,
                       'bht_size' => 512,
                       'bht_ghr_hash_1' => '',
                       'bht_array_depth' => 256,
                       'bht_addr_hi' => 9,
                       'bht_ghr_range' => '7:0',
                       'bht_addr_lo' => '2',
                       'bht_hash_string' => '{hashin[8+1:2]^ghr[8-1:0]}// cf2'
                     },
            'target' => 'default',
            'perf_events' => [
                               1,
                               2,
                               3,
                               4,
                               5,
                               6,
                               7,
                               8,
                               9,
                               10,
                               11,
                               12,
                               13,
                               14,
                               15,
                               16,
                               17,
                               18,
                               19,
                               20,
                               21,
                               22,
                               23,
                               24,
                               25,
                               26,
                               27,
                               28,
                               30,
                               31,
                               32,
                               34,
                               35,
                               36,
                               37,
                               38,
                               39,
                               40,
                               41,
                               42,
                               43,
                               44,
                               45,
                               46,
                               47,
                               48,
                               49,
                               50,
                               54,
                               55,
                               56,
                               512,
                               513,
                               514,
                               515,
                               516
                             ],
            'dccm' => {
                        'dccm_bits' => 16,
                        'dccm_size_64' => '',
                        'dccm_reserved' => '0x1400',
                        'dccm_num_banks_4' => '',
                        'dccm_enable' => '1',
                        'lsu_sb_bits' => 16,
                        'dccm_num_banks' => '4',
                        'dccm_fdata_width' => 39,
                        'dccm_width_bits' => 2,
                        'dccm_ecc_width' => 7,
                        'dccm_sadr' => '0xf0040000',
                        'dccm_eadr' => '0xf004ffff',
                        'dccm_byte_width' => '4',
                        'dccm_offset' => '0x40000',
                        'dccm_region' => '0xf',
                        'dccm_bank_bits' => 2,
                        'dccm_data_width' => 32,
                        'dccm_index_bits' => 12,
                        'dccm_data_cell' => 'ram_4096x39',
                        'dccm_rows' => '4096',
                        'dccm_size' => 64
                      },
            'iccm' => {
                        'iccm_size' => 64,
                        'iccm_enable' => 1,
                        'iccm_bits' => 16,
                        'iccm_index_bits' => 12,
                        'iccm_bank_index_lo' => 4,
                        'iccm_rows' => '4096',
                        'iccm_ecc_width' => '7',
                        'iccm_data_cell' => 'ram_4096x39',
                        'iccm_num_banks' => '4',
                        'iccm_bank_bits' => 2,
                        'iccm_eadr' => '0xee00ffff',
                        'iccm_sadr' => '0xee000000',
                        'iccm_size_64' => '',
                        'iccm_reserved' => '0x1000',
                        'iccm_num_banks_4' => '',
                        'iccm_offset' => '0xe000000',
                        'iccm_region' => '0xe',
                        'iccm_bank_hi' => 3
                      },
            'protection' => {
                              'inst_access_addr2' => '0x00000000',
                              'inst_access_addr0' => '0x00000000',
                              'inst_access_enable3' => '0x0',
                              'inst_access_enable2' => '0x0',
                              'inst_access_addr7' => '0x00000000',
                              'inst_access_mask6' => '0xffffffff',
                              'data_access_addr3' => '0x00000000',
                              'inst_access_enable5' => '0x0',
                              'data_access_mask3' => '0xffffffff',
                              'data_access_mask5' => '0xffffffff',
                              'inst_access_mask5' => '0xffffffff',
                              'inst_access_addr3' => '0x00000000',
                              'data_access_addr4' => '0x00000000',
                              'data_access_mask4' => '0xffffffff',
                              'inst_access_addr6' => '0x00000000',
                              'inst_access_mask1' => '0xffffffff',
                              'inst_access_mask2' => '0xffffffff',
                              'data_access_addr0' => '0x00000000',
                              'pmp_entries' => '16',
                              'inst_access_addr1' => '0x00000000',
                              'data_access_mask6' => '0xffffffff',
                              'data_access_enable2' => '0x0',
                              'inst_access_enable0' => '0x0',
                              'data_access_enable3' => '0x0',
                              'data_access_enable1' => '0x0',
                              'data_access_addr7' => '0x00000000',
                              'inst_access_mask0' => '0xffffffff',
                              'data_access_addr6' => '0x00000000',
                              'data_access_addr2' => '0x00000000',
                              'inst_access_mask4' => '0xffffffff',
                              'data_access_enable7' => '0x0',
                              'data_access_mask7' => '0xffffffff',
                              'inst_access_enable6' => '0x0',
                              'inst_access_addr5' => '0x00000000',
                              'inst_access_enable7' => '0x0',
                              'inst_access_mask7' => '0xffffffff',
                              'inst_access_addr4' => '0x00000000',
                              'inst_access_mask3' => '0xffffffff',
                              'inst_access_enable1' => '0x0',
                              'data_access_mask2' => '0xffffffff',
                              'inst_access_enable4' => '0x0',
                              'data_access_enable5' => '0x0',
                              'data_access_addr5' => '0x00000000',
                              'data_access_addr1' => '0x00000000',
                              'data_access_mask0' => '0xffffffff',
                              'data_access_mask1' => '0xffffffff',
                              'data_access_enable0' => '0x0',
                              'data_access_enable4' => '0x0',
                              'data_access_enable6' => '0x0'
                            },
            'bus' => {
                       'ifu_bus_tag' => '3',
                       'lsu_bus_id' => '1',
                       'ifu_bus_id' => '1',
                       'dma_bus_id' => '1',
                       'dma_bus_tag' => '1',
                       'lsu_bus_prty' => '2',
                       'bus_prty_default' => '3',
                       'sb_bus_tag' => '1',
                       'dma_bus_prty' => '2',
                       'sb_bus_id' => '1',
                       'sb_bus_prty' => '2',
                       'lsu_bus_tag' => 3,
                       'ifu_bus_prty' => '2'
                     }
          );
1;
