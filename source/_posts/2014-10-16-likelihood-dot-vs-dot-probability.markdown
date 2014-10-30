---
layout: post
title: "Likelihood和Probability的区别"
date: 2014-10-16 10:26:42 +0800
comments: true
categories: 
---

Likelihood(似然性)和Probalility(可能性)在机器学习和统计学中经常遇到，容易混淆。特别上网查询，以便澄清。

##几种说法
### Mathworld
<http://mathworld.wolfram.com/Likelihood.html>

***Likelihood*** *is the hypothetical probability that an event that has already occurred would yield a specific outcome. The concept differs from that of a probability in that a probability refers to the occurrence of future events, while a likelihood refers to past events with known outcomes.*

似然性是已发生的事件产生特定结果的假设概率。这个概念不同于概率的地方在于，概率指代未来事件的发生，而似然性指代有已知结果的过去事件。


### Wiki
<http://en.wikipedia.org/wiki/Likelihood_function>

*Likelihood functions play a key role in statistical inference, especially methods of estimating a parameter from a set of statistics. In informal contexts, "likelihood" is often used as a synonym for "probability." But in statistical usage, a distinction is made depending on the roles of the outcome or parameter. Probability is used when describing a function of the outcome given a fixed parameter value. For example, if a coin is flipped 10 times and it is a fair coin, what is the probability of it landing heads-up every time? Likelihood is used when describing a function of a parameter given an outcome. For example, if a coin is flipped 10 times and it has landed heads-up 10 times, what is the likelihood that the coin is fair? *


在非正式的语境下，likelihood经常是probaility的同义词。但在统计学中，根据参数和输出的角色不同，用法上仍有不同。可能性，经常用于描述，当给定参数值时，输出的函数。例如，如果将一个硬币抛10次，而硬币没问题，那么它每次正面朝上的概率有多大？而Likelihood用于描述，当给定结果时，参数的函数。例如，如果抛硬币10次，每次都正面朝上，那么硬币没问题的似然性有多大？

### Ben Klemens的文章
<http://modelingwithdata.org/pdfs/024-like_probably.pdf>


##总结

* Possibility(概率)是给定参数后，针对数据的函数。而Likelihood(似然性)是给定数据后，针对参数的函数。
* Possibility是后验的、可测量的、客观的。而Likelihood则是先验的、不可测量的，由人主观构思的。
* 可以通过Bayes's法则将二者联系起来
*