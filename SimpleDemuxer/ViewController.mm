//
//  ViewController.m
//  SimpleDemuxer
//
//  Created by yinggeli on 16/10/4.
//  Copyright © 2016年 LYG. All rights reserved.
//

#import "ViewController.h"

int doDemuxTest();
int doAmendPtsofPacketTest();

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    doDemuxTest();
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
