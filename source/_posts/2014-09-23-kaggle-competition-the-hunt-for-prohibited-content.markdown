---
layout: post
title: "Kaggle Competition: The Hunt for Prohibited Content"
date: 2014-09-23 10:42:26 +0800
comments: true
categories: 
---
# 简介
当我开始留意这个竞赛时，已接近尾声。还有个原因，竞赛的进展超出了主办发的预期，他们迫不及待想看看结果，于是就提前结束了竞赛([Timeline Change](http://www.kaggle.com/c/avito-prohibited-content/forums/t/9721/timeline-change/))。

由于最近在熟悉[vowpal wabbit](https://github.com/JohnLangford/vowpal_wabbit/wiki)，这是一个非常快速的线性模型学习工具，用起来象瑞士军刀那样爽。[mlwave.com的文章](http://mlwave.com/lessons-from-avito-prohibited-content-kaggle/)介绍了使用vw参赛的经验。另外，yr也用[vw参赛](http://www.kaggle.com/c/avito-prohibited-content/forums/t/10178/congrats-barisumog-giulio/52810#post52810)，取得了No.4的好成绩。本文主要就其[程序](https://github.com/ChenglongChen/Kaggle_The_Hunt_for_Prohibited_Content)进行分析，重新实验。虽然是赛后的分析，仍具有相当价值。



# 背景

[avito.ru](avito.ru)是俄罗斯最大的分类网站，它将俄罗斯各个地区的买家和卖家连接起来。其上大约有2200万活跃广告，而且每天都在大量的广告在增加或调整。Avito的效率，很大程度上取决于内容的质量 -- 在几小时内，买家能迅速找到相关的商品，而卖家能迅速销售出商品。

当Avito规模越大、越受欢迎时，销售非法商品或服务的吸引力也会越大。有些商品一看就知道是非法的，但还有些商品看似合法的，但并不符合网站的规则。
Kaggle的竞赛 [The Hunt for Prohibited Content](http://www.kaggle.com/c/avito-prohibited-content) 由俄罗斯最大的分类的 发起，是预测被禁止的广告。所以，很多新增或修改的广告都要经过人工的审查。如果广告违反了俄罗斯法律或avito内部的规则，就会被删除。但是，随着业务增长，彻底审查所有广告越来越具有挑战性。这就是机器学习发挥作用的地方。

这个竞赛的目的是创建一个预测性模型，它可以从审查员的判断中去学习，然后预测一个广告是否含有非法信息。


# 数据
测试集有3,995,804行。训练集有1,351,242，为训练集的1/3。

# 基本算法(Baseline)
0.97197(0.97095)

# yr的算法

yr的算法，Score分别为：0.98507(0.98628)。

## Features Engineering
Score为0.97503(0.97630)。看来ensamble提高了接近1个百分点。

## Grid Search
learning rate = 0.5, learning rate decay = 1.0, passes = 10

0.97629(0.97653), 提高了1个百分点。

## Split proved & unproved
proved: 0.97629(0.97653)

## Ensemble
mixed ensemble mean: 0.98497(0.98504)。
mixed ensamble median: 0.98498(0.98447)。

proved ensamble mean: 0.98363(0.98474)。
proved ensamble median: 0.98329(0.98448)。

