-- phpMyAdmin SQL Dump
-- version 4.8.4
-- https://www.phpmyadmin.net/
--
-- Host: 
-- Generation Time: Mar 16, 2019 at 04:50 PM
-- Server version: 10.1.37-MariaDB
-- PHP Version: 7.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET AUTOCOMMIT = 0;
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `store`
--

-- --------------------------------------------------------

--
-- Table structure for table `store_categories`
--

CREATE TABLE `store_categories` (
  `server_id` tinyint(4) NOT NULL,
  `categories` set('ctplayermodel','tplayermodel','chattitle','chatcolor') NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Dumping data for table `store_categories`
--

INSERT INTO `store_categories` (`server_id`, `categories`) VALUES
(1, 'ctplayermodel,tplayermodel,chattitle,chatcolor');

-- --------------------------------------------------------

--
-- Table structure for table `store_equipped_items`
--

CREATE TABLE `store_equipped_items` (
  `id` int(11) NOT NULL,
  `owner_id` int(11) NOT NULL,
  `slot` int(11) NOT NULL,
  `item_id` int(11) NOT NULL DEFAULT '-1'
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `store_inventories`
--

CREATE TABLE `store_inventories` (
  `id` int(11) NOT NULL,
  `item_id` int(11) NOT NULL DEFAULT '0',
  `server_id` tinyint(4) NOT NULL,
  `owner_id` int(11) NOT NULL DEFAULT '0'
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

-- --------------------------------------------------------

--
-- Table structure for table `store_items`
--

CREATE TABLE `store_items` (
  `id` int(11) NOT NULL,
  `type` enum('ctplayermodel','tplayermodel','chattitle','chatcolor') DEFAULT NULL,
  `enabled` tinyint(4) NOT NULL DEFAULT '1',
  `price` int(11) NOT NULL DEFAULT '100',
  `display` varchar(50) NOT NULL DEFAULT 'undefined',
  `description` varchar(50) DEFAULT NULL,
  `value` varchar(100) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --------------------------------------------------------

--
-- Table structure for table `store_users`
--

CREATE TABLE `store_users` (
  `id` int(11) NOT NULL,
  `auth` varchar(50) NOT NULL,
  `lastlogin` int(11) NOT NULL,
  `name` varchar(50) CHARACTER SET utf8mb4 DEFAULT NULL,
  `credits` int(11) NOT NULL DEFAULT '0'
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

  `server_id` TINYINT(4) NOT NULL,
  `categories` SET('playermodel','chattitle','chatcolor') NOT NULL,

--
-- Indexes for table `store_categories`
--
ALTER TABLE `store_categories`
  ADD PRIMARY KEY (`server_id`);

--
-- Indexes for table `store_equipped_items`
--
ALTER TABLE `store_equipped_items`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `owner_id_slot` (`owner_id`,`slot`),
  ADD KEY `owner_item_ids` (`owner_id`,`item_id`);

--
-- Indexes for table `store_inventories`
--
ALTER TABLE `store_inventories`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `itempair` (`item_id`,`owner_id`),
  ADD KEY `item_id` (`item_id`),
  ADD KEY `owner_id` (`owner_id`),
  ADD KEY `server_id` (`server_id`);

--
-- Indexes for table `store_items`
--
ALTER TABLE `store_items`
  ADD PRIMARY KEY (`id`),
  ADD KEY `type` (`type`);

--
-- Indexes for table `store_users`
--
ALTER TABLE `store_users`
  ADD PRIMARY KEY (`id`),
  ADD KEY `auth` (`auth`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `store_equipped_items`
--
ALTER TABLE `store_equipped_items`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=17;

--
-- AUTO_INCREMENT for table `store_inventories`
--
ALTER TABLE `store_inventories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT for table `store_items`
--
ALTER TABLE `store_items`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=21;

--
-- AUTO_INCREMENT for table `store_users`
--
ALTER TABLE `store_users`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
