-- DATABASE GỐC + TÊN/ẢNH PHÒNG + MÃ GIẢM GIÁ + HỒ SƠ PHÒNG
-- Tạo phần còn thiếu, giữ dữ liệu hiện có.

USE master;
GO

IF DB_ID(N'booking_db') IS NULL
    EXEC(N'CREATE DATABASE booking_db');
GO

USE booking_db;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;

IF @@TRANCOUNT<>0
    THROW 51000,N'Hãy mở New Query không có giao dịch đang dang dở.',1;

BEGIN TRY
BEGIN TRANSACTION;

IF DB_NAME()<>N'booking_db'
    THROW 51000,N'Chưa chọn đúng database booking_db.',1;

-- =====================================================
-- 1. CÁC BẢNG GỐC
-- =====================================================

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.Users'',N''U'') IS NULL
BEGIN
 CREATE TABLE dbo.Users(
  user_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  ho_ten NVARCHAR(255) NULL,
  email VARCHAR(255) NULL UNIQUE,
  mat_khau VARCHAR(255) NULL,
  so_dien_thoai VARCHAR(20) NULL,
  vai_tro NVARCHAR(50) DEFAULT N''Khách hàng''
 );
END;
';

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.Room_Types'',N''U'') IS NULL
BEGIN
 CREATE TABLE dbo.Room_Types(
  type_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  ten_loai NVARCHAR(150) NULL,
  gia_tien DECIMAL(18,2) NULL,
  suc_chua INT DEFAULT 2,
  dien_tich NVARCHAR(50) NULL,
  giuong NVARCHAR(100) NULL,
  view_phong NVARCHAR(100) NULL,
  tien_nghi NVARCHAR(500) NULL,
  co_an_sang BIT DEFAULT 1
 );
END;
';

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.Rooms'',N''U'') IS NULL
BEGIN
 CREATE TABLE dbo.Rooms(
  room_id VARCHAR(50) NOT NULL PRIMARY KEY,
  type_id INT NULL,
  ten_phong NVARCHAR(150) NULL,
  hinh_anh NVARCHAR(1000) NULL,
  CONSTRAINT FK_Rooms_RoomTypes FOREIGN KEY(type_id)
   REFERENCES dbo.Room_Types(type_id) ON DELETE SET NULL
 );
END;
';

EXEC sys.sp_executesql N'
IF COL_LENGTH(N''dbo.Rooms'',N''ten_phong'') IS NULL
 ALTER TABLE dbo.Rooms ADD ten_phong NVARCHAR(150) NULL;

IF COL_LENGTH(N''dbo.Rooms'',N''hinh_anh'') IS NULL
 ALTER TABLE dbo.Rooms ADD hinh_anh NVARCHAR(1000) NULL;
';

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.Bookings'',N''U'') IS NULL
BEGIN
 CREATE TABLE dbo.Bookings(
  booking_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  user_id INT NULL,
  ngay_checkin DATE NULL,
  ngay_checkout DATE NULL,
  ngay_dat DATETIME DEFAULT DATEADD(HOUR,7,GETUTCDATE()),
  so_nguoi_lon INT DEFAULT 2,
  so_tre_em INT DEFAULT 0,
  tong_tien DECIMAL(18,2) NULL,
  phuong_thuc_tt NVARCHAR(100) DEFAULT N''Thanh toán tại khách sạn'',
  ghi_chu NVARCHAR(500) NULL,
  trang_thai NVARCHAR(50) DEFAULT N''Đã xác nhận'',
  CONSTRAINT FK_Bookings_Users FOREIGN KEY(user_id)
   REFERENCES dbo.Users(user_id) ON DELETE CASCADE
 );
END;
';

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.Booking_Details'',N''U'') IS NULL
BEGIN
 CREATE TABLE dbo.Booking_Details(
  detail_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  booking_id INT NULL,
  room_id VARCHAR(50) NULL,
  don_gia DECIMAL(18,2) NULL,
  CONSTRAINT FK_Details_Bookings FOREIGN KEY(booking_id)
   REFERENCES dbo.Bookings(booking_id) ON DELETE CASCADE,
  CONSTRAINT FK_Details_Rooms FOREIGN KEY(room_id)
   REFERENCES dbo.Rooms(room_id) ON DELETE SET NULL
 );
END;
';

-- =====================================================
-- 2. MÃ GIẢM GIÁ, NGÀY LỄ, DỊCH VỤ ĐI KÈM ĐƠN PHÒNG
-- =====================================================

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.DiscountCodes'',N''U'') IS NULL
BEGIN
 CREATE TABLE dbo.DiscountCodes(
  code NVARCHAR(32) NOT NULL PRIMARY KEY,
  discount_percent DECIMAL(5,2) NOT NULL
   CHECK(discount_percent>0 AND discount_percent<=100),
  enabled BIT NOT NULL DEFAULT 1,
  valid_from DATE NULL,
  valid_to DATE NULL,
  kind NVARCHAR(16) NOT NULL DEFAULT N''ALL'',
  CHECK(valid_from IS NULL OR valid_to IS NULL OR valid_to>=valid_from)
 );
END;
';

EXEC sys.sp_executesql N'
IF COL_LENGTH(N''dbo.DiscountCodes'',N''kind'') IS NULL
 ALTER TABLE dbo.DiscountCodes
 ADD kind NVARCHAR(16) NOT NULL DEFAULT N''ALL'';
';

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.HolidayDates'',N''U'') IS NULL
BEGIN
 CREATE TABLE dbo.HolidayDates(
  holiday_date DATE NOT NULL PRIMARY KEY,
  holiday_name NVARCHAR(150) NOT NULL
 );
END;
';

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.Booking_Options'',N''U'') IS NULL
BEGIN
 CREATE TABLE dbo.Booking_Options(
  booking_id INT NOT NULL PRIMARY KEY,
  services NVARCHAR(200) NOT NULL,
  service_total DECIMAL(18,2) NOT NULL,
  discount_code NVARCHAR(32) NULL,
  discount_percent DECIMAL(5,2) NOT NULL,
  discount_amount DECIMAL(18,2) NOT NULL,
  CONSTRAINT FK_Booking_Options_Bookings FOREIGN KEY(booking_id)
   REFERENCES dbo.Bookings(booking_id) ON DELETE CASCADE
 );
END;
';

EXEC sys.sp_executesql N'
IF NOT EXISTS(
 SELECT 1 FROM sys.indexes
 WHERE name=N''IX_Booking_Details_RoomBooking''
 AND object_id=OBJECT_ID(N''dbo.Booking_Details'')
)
 CREATE INDEX IX_Booking_Details_RoomBooking
 ON dbo.Booking_Details(room_id,booking_id);
';

-- =====================================================
-- 3. LOẠI PHÒNG MẪU
-- Chỉ thêm loại còn thiếu, không đặt lại giá loại đã có.
-- =====================================================

EXEC sys.sp_executesql N'
INSERT dbo.Room_Types(
 ten_loai,gia_tien,suc_chua,dien_tich,
 giuong,view_phong,tien_nghi,co_an_sang
)
SELECT v.ten_loai,v.gia_tien,v.suc_chua,v.dien_tich,
 v.giuong,v.view_phong,v.tien_nghi,1
FROM(VALUES
(
 N''Phòng Superior'',1200000,2,N''30 m²'',
 N''1 Giường đôi'',N''Hướng phố'',
 N''Wifi, Máy lạnh, Bồn tắm''
),
(
 N''Phòng Deluxe'',1800000,2,N''35 m²'',
 N''1 Giường King'',N''Hướng phố'',
 N''Wifi, Ban công, Minibar''
),
(
 N''Phòng Hướng Biển'',2500000,2,N''40 m²'',
 N''1 Giường King'',N''Hướng biển'',
 N''Ban công ngắm biển, Bồn tắm''
),
(
 N''Phòng Gia Đình'',3200000,4,N''55 m²'',
 N''2 Giường đôi'',N''Hướng phố'',
 N''2 Phòng ngủ, Bếp mini''
),
(
 N''Phòng Suite'',4500000,2,N''65 m²'',
 N''1 Giường Super King'',N''Hướng biển'',
 N''Phòng khách riêng, Bồn jacuzzi''
),
(
 N''Phòng Cao Cấp'',6000000,4,N''85 m²'',
 N''2 Giường King'',N''Hướng biển 360 độ'',
 N''Hồ bơi riêng, Quản gia 24/7''
)
)v(ten_loai,gia_tien,suc_chua,dien_tich,giuong,view_phong,tien_nghi)
WHERE NOT EXISTS(
 SELECT 1 FROM dbo.Room_Types t WHERE t.ten_loai=v.ten_loai
);
';

-- =====================================================
-- 4. TÊN VÀ ẢNH PHÒNG
-- =====================================================

EXEC sys.sp_executesql N'
DECLARE @RoomSeed TABLE(
 room_id VARCHAR(50),
 ten_loai NVARCHAR(150),
 ten_phong NVARCHAR(150),
 hinh_anh NVARCHAR(1000)
);

INSERT @RoomSeed VALUES
(
 ''P101'',N''Phòng Superior'',N''Silver Moon'',
 N''https://poliva.vn/wp-content/uploads/2019/08/phong-Superior-3.jpg''
),
(
 ''P102'',N''Phòng Superior'',N''Lavender Dream'',
 N''https://yiwin.vn/wp-content/uploads/2025/09/Phong-Superior-Double.jpg''
),
(
 ''P201'',N''Phòng Deluxe'',N''Royal Velvet'',
 N''https://aftavietnam.com.vn/wp-content/uploads/2024/01/phong-deluxe-la-gi-co-nen-chon-phong-deluxe-khong-22960-7.jpg''
),
(
 ''P202'',N''Phòng Deluxe'',N''Golden Hour'',
 N''https://hoteldelamourtamdao.com/wp-content/uploads/2023/06/Deluxe-King-1.jpg''
),
(
 ''P301'',N''Phòng Hướng Biển'',N''Ocean Pearl'',
 N''https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTkPbTJ9iaShfU1TS_sjVcUXBZXdnN7uikr07ya0d7YTw&s=10''
),
(
 ''P302'',N''Phòng Hướng Biển'',N''Azure Horizon'',
 N''https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=800&q=80''
),
(
 ''P401'',N''Phòng Gia Đình'',N''Family Paradise'',
 N''https://images.unsplash.com/photo-1596394516093-501ba68a0ba6?auto=format&fit=crop&w=800&q=80''
),
(
 ''P402'',N''Phòng Gia Đình'',N''Family Suite Haven'',
 N''https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=800&q=80''
),
(
 ''P501'',N''Phòng Suite'',N''Presidential Suite'',
 N''https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=800&q=80''
),
(
 ''P502'',N''Phòng Suite'',N''Imperial Suite'',
 N''https://images.unsplash.com/photo-1631049307264-da0ec9d70304?auto=format&fit=crop&w=800&q=80''
),
(
 ''P601'',N''Phòng Cao Cấp'',N''Penthouse Luxury'',
 N''https://images.unsplash.com/photo-1590490360182-c33d57733427?auto=format&fit=crop&w=800&q=80''
),
(
 ''P602'',N''Phòng Cao Cấp'',N''Royal Crown Villa'',
 N''https://images.unsplash.com/photo-1618773928121-c32242e63f39?auto=format&fit=crop&w=800&q=80''
);

INSERT dbo.Rooms(room_id,type_id,ten_phong,hinh_anh)
SELECT s.room_id,t.type_id,s.ten_phong,s.hinh_anh
FROM @RoomSeed s
CROSS APPLY(
 SELECT TOP(1) type_id
 FROM dbo.Room_Types
 WHERE ten_loai=s.ten_loai
 ORDER BY type_id
)t
WHERE NOT EXISTS(
 SELECT 1 FROM dbo.Rooms r WHERE r.room_id=s.room_id
);

UPDATE r SET
 ten_phong=CASE
  WHEN NULLIF(LTRIM(RTRIM(r.ten_phong)),N'''') IS NULL
  THEN s.ten_phong ELSE r.ten_phong END,
 hinh_anh=CASE
  WHEN NULLIF(LTRIM(RTRIM(r.hinh_anh)),N'''') IS NULL
  THEN s.hinh_anh ELSE r.hinh_anh END
FROM dbo.Rooms r
JOIN dbo.Room_Types t ON t.type_id=r.type_id
JOIN @RoomSeed s ON s.room_id=r.room_id AND s.ten_loai=t.ten_loai;
';

-- =====================================================
-- 5. MÃ GIẢM GIÁ VÀ NGÀY LỄ MẪU
-- Điều kiện sử dụng mã được kiểm tra trong controller.
-- =====================================================

EXEC sys.sp_executesql N'
INSERT dbo.DiscountCodes(code,discount_percent,enabled,kind)
SELECT v.code,v.rate,1,v.kind
FROM(VALUES
 (N''VIP15'',15,N''VIP''),
 (N''MOI10'',10,N''NEW''),
 (N''LE10'',10,N''HOLIDAY'')
)v(code,rate,kind)
WHERE NOT EXISTS(
 SELECT 1 FROM dbo.DiscountCodes WHERE code=v.code
);
';

EXEC sys.sp_executesql N'
DECLARE @year INT=YEAR(DATEADD(HOUR,7,GETUTCDATE()));

;WITH years AS(
 SELECT @year AS y
 UNION ALL
 SELECT y+1 FROM years WHERE y<@year+5
)
INSERT dbo.HolidayDates(holiday_date,holiday_name)
SELECT DATEFROMPARTS(y,h.m,h.d),h.name
FROM years
CROSS JOIN(VALUES
 (1,1,N''Tết Dương lịch''),
 (4,30,N''Ngày 30/4''),
 (5,1,N''Quốc tế Lao động''),
 (9,2,N''Quốc khánh'')
)h(m,d,name)
WHERE NOT EXISTS(
 SELECT 1 FROM dbo.HolidayDates
 WHERE holiday_date=DATEFROMPARTS(y,h.m,h.d)
);
';

EXEC sys.sp_executesql N'
INSERT dbo.HolidayDates(holiday_date,holiday_name)
SELECT v.d,N''Tết Nguyên đán''
FROM(VALUES
 (CONVERT(DATE,''20260217'')),
 (CONVERT(DATE,''20270206''))
)v(d)
WHERE NOT EXISTS(
 SELECT 1 FROM dbo.HolidayDates WHERE holiday_date=v.d
);
';

-- =====================================================
-- 6. BẢNG HỒ SƠ PHÒNG
-- =====================================================

EXEC sys.sp_executesql N'
IF OBJECT_ID(N''dbo.Room_Profiles'',N''U'') IS NULL
BEGIN
 CREATE TABLE dbo.Room_Profiles(
  room_id VARCHAR(50) NOT NULL PRIMARY KEY,
  mo_ta NVARCHAR(1200) NOT NULL,
  khong_gian NVARCHAR(1000) NOT NULL,
  phong_tam NVARCHAR(1000) NOT NULL,
  thiet_bi NVARCHAR(1000) NOT NULL,
  tien_ich NVARCHAR(1200) NOT NULL,
  phu_hop NVARCHAR(600) NOT NULL,
  luu_y NVARCHAR(1000) NOT NULL,
  nguon_tham_khao NVARCHAR(1500) NULL,
  la_noi_dung_mau BIT NOT NULL DEFAULT 1,
  cap_nhat_luc DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  CONSTRAINT FK_Room_Profiles_Rooms FOREIGN KEY(room_id)
   REFERENCES dbo.Rooms(room_id) ON DELETE CASCADE
 );
END;
';

-- =====================================================
-- 7. NỘI DUNG HỒ SƠ PHÒNG
-- Chỉ tạo hồ sơ chưa tồn tại, giữ nguyên hồ sơ đã có.
-- =====================================================

EXEC sys.sp_executesql N'
DECLARE @Types TABLE(
 ten_loai NVARCHAR(150),
 mo_ta NVARCHAR(1200),
 khong_gian NVARCHAR(1000),
 phong_tam NVARCHAR(1000),
 thiet_bi NVARCHAR(1000),
 tien_ich NVARCHAR(1200),
 phu_hop NVARCHAR(600),
 nguon NVARCHAR(1500)
);

INSERT @Types VALUES
(
 N''Phòng Superior'',
 N''Không gian nghỉ ngơi gọn gàng, ưu tiên sự tiện dụng cho chuyến công tác hoặc kỳ nghỉ ngắn.'',
 N''Khu vực ngủ với đèn đọc sách|Bàn làm việc hoặc bàn trang điểm|Tủ quần áo và chỗ để hành lý|Rèm che sáng'',
 N''Phòng tắm riêng có nước nóng|Vòi sen|Máy sấy tóc|Khăn tắm và đồ dùng vệ sinh cơ bản'',
 N''TV màn hình phẳng và kênh truyền hình|Điều hòa điều chỉnh trong phòng|Wi-Fi|Điện thoại nội bộ|Két an toàn|Ấm đun nước'',
 N''Trà và cà phê|Minibar có tính phí|Dọn phòng theo lịch khách sạn'',
 N''Khách công tác|Khách đi một mình|Cặp đôi nghỉ ngắn ngày'',
 N''https://www.navadahotel.com/superior-twin-room-with-city-view-6-23-1-room-single.html''
),
(
 N''Phòng Deluxe'',
 N''Phòng nghỉ có thêm không gian thư giãn, kết hợp khu vực làm việc và các tiện ích phục vụ lưu trú thoải mái.'',
 N''Góc ngồi thư giãn|Bàn làm việc và gương trang điểm|Tủ quần áo, chỗ để hành lý|Rèm che sáng'',
 N''Phòng tắm riêng|Bồn tắm hoặc khu vực tắm đứng theo bố trí phòng|Máy sấy tóc|Khăn tắm, dép và áo choàng'',
 N''TV màn hình phẳng|Điều hòa điều chỉnh trong phòng|Wi-Fi|Két an toàn|Ấm đun nước và bộ tách trà|Minibar'',
 N''Trà, cà phê trong phòng|Bàn ủi theo yêu cầu|Dịch vụ ăn uống tại phòng có tính phí'',
 N''Cặp đôi|Khách công tác cần góc làm việc|Khách lưu trú nhiều ngày'',
 N''https://havanahotel.vn/en/rooms/deluxe-huong-bien''
),
(
 N''Phòng Hướng Biển'',
 N''Không gian nghỉ dưỡng hướng ra biển, có góc ngồi ngắm cảnh và các tiện nghi phục vụ kỳ nghỉ bên bờ biển.'',
 N''Cửa kính đón ánh sáng và hướng nhìn ra biển|Góc ngồi thư giãn cạnh cửa sổ|Ban công theo bố trí phòng|Tủ quần áo và chỗ để hành lý'',
 N''Phòng tắm riêng có nước nóng|Vòi sen và đồ dùng vệ sinh|Máy sấy tóc|Khăn tắm, dép và áo choàng'',
 N''TV màn hình phẳng|Wi-Fi|Điều hòa điều chỉnh trong phòng|Két an toàn|Ấm đun nước|Minibar'',
 N''Trà và cà phê|Bàn ghế thư giãn|Dọn phòng theo lịch khách sạn'',
 N''Cặp đôi nghỉ dưỡng|Khách yêu thích ngắm biển|Khách muốn không gian thư giãn có ánh sáng tự nhiên'',
 N''https://www.navadahotel.com/deluxe-twin-room-with-sea-view-and-with-balcony-11-23-1-room-single.html''
),
(
 N''Phòng Gia Đình'',
 N''Không gian lưu trú cho gia đình hoặc nhóm nhỏ, kết hợp khu vực nghỉ ngơi và góc sinh hoạt chung thuận tiện.'',
 N''Khu vực ngủ cho gia đình theo cấu hình giường đã công bố|Sofa và góc sinh hoạt chung|Bàn ăn nhỏ|Bếp nhỏ và tủ lạnh'',
 N''Phòng tắm riêng|Vòi sen hoặc bồn tắm theo bố trí|Máy sấy tóc|Khăn tắm và đồ dùng vệ sinh'',
 N''TV màn hình phẳng|Wi-Fi|Điều hòa|Két an toàn|Ấm đun nước|Lò vi sóng tại khu bếp'',
 N''Dụng cụ ăn uống cơ bản|Hỗ trợ nôi em bé theo yêu cầu và tình trạng sẵn có|Dọn phòng theo lịch khách sạn'',
 N''Gia đình có trẻ nhỏ|Nhóm bạn trong giới hạn sức chứa|Khách lưu trú dài ngày'',
 N''https://havanahotel.vn/en/rooms/family-suite''
),
(
 N''Phòng Suite'',
 N''Không gian nghỉ dưỡng có khu tiếp khách riêng, phù hợp với khách cần sự riêng tư và tiện nghi thư giãn cao hơn.'',
 N''Khu vực ngủ và phòng khách riêng|Sofa cùng bàn trà|Bàn làm việc|Tủ quần áo và chỗ để hành lý'',
 N''Phòng tắm rộng|Bồn tắm Jacuzzi theo cấu hình phòng|Khu vực vòi sen|Máy sấy tóc, áo choàng và dép'',
 N''TV màn hình phẳng|Wi-Fi|Điều hòa|Két an toàn|Minibar|Bộ pha trà và cà phê'',
 N''Góc tiếp khách riêng|Dịch vụ ăn uống tại phòng có tính phí|Bàn ủi theo yêu cầu|Dọn phòng theo lịch khách sạn'',
 N''Cặp đôi nghỉ dưỡng|Khách công tác cần không gian tiếp khách|Khách ưu tiên sự riêng tư'',
 N''https://havanahotel.vn/en/rooms/junior-suite-king|https://havanahotel.vn/en/rooms/executive-suite''
),
(
 N''Phòng Cao Cấp'',
 N''Không gian nghỉ dưỡng riêng tư lấy cảm hứng từ các villa cao cấp, kết hợp khu sinh hoạt trong nhà và khu thư giãn ngoài trời.'',
 N''Khu vực ngủ theo cấu hình giường đã công bố|Phòng khách với sofa|Bàn ăn và bếp nhỏ|Sân hiên hoặc khu ngồi ngoài trời'',
 N''Phòng tắm riêng|Bồn tắm và khu vực vòi sen|Máy sấy tóc|Áo choàng, dép và đồ dùng vệ sinh'',
 N''TV màn hình phẳng|Wi-Fi|Điều hòa|Két an toàn|Tủ lạnh hoặc minibar|Bộ pha trà và cà phê'',
 N''Hồ bơi riêng theo cấu hình phòng|Khu vực thư giãn ngoài trời|Hỗ trợ quản gia theo lịch phục vụ|Ăn uống riêng có tính phí'',
 N''Gia đình nghỉ dưỡng|Nhóm nhỏ trong giới hạn sức chứa|Khách cần không gian riêng tư'',
 N''https://vinpearl.com/en/hotels/vinpearl-resort-nha-trang''
);

BEGIN TRANSACTION;

DECLARE @Created TABLE(room_id VARCHAR(50) PRIMARY KEY);

INSERT dbo.Room_Profiles(
 room_id,mo_ta,khong_gian,phong_tam,thiet_bi,
 tien_ich,phu_hop,luu_y,nguon_tham_khao
)
OUTPUT inserted.room_id INTO @Created
SELECT
 r.room_id,p.mo_ta,p.khong_gian,p.phong_tam,p.thiet_bi,
 p.tien_ich,p.phu_hop,
 N''Nội dung tiện nghi minh họa, chờ khách sạn xác nhận.|Minibar, ăn uống và các dịch vụ bổ sung có thể tính phí.|Các yêu cầu đặc biệt tùy tình trạng sẵn có.'',
 p.nguon
FROM dbo.Rooms r
JOIN dbo.Room_Types t ON t.type_id=r.type_id
JOIN @Types p ON p.ten_loai=t.ten_loai
WHERE NOT EXISTS(
 SELECT 1 FROM dbo.Room_Profiles x WHERE x.room_id=r.room_id
);

UPDATE p SET
 mo_ta=v.mo_ta,
 khong_gian=v.khong_gian,
 tien_ich=v.tien_ich
FROM dbo.Room_Profiles p
JOIN @Created c ON c.room_id=p.room_id
JOIN(VALUES
(
 ''P101'',
 N''Phòng nghỉ gọn gàng với góc làm việc và khu vực cất hành lý thuận tiện, phù hợp chuyến công tác ngắn.'',
 N''Khu vực ngủ với đèn đọc sách|Bàn làm việc|Tủ quần áo|Kệ để hành lý'',
 N''Trà, cà phê và ấm đun nước|Minibar có tính phí|Két an toàn trong phòng''
),
(
 ''P102'',
 N''Phòng nghỉ mang phong cách nhẹ nhàng, có góc trang điểm và ghế thư giãn cho kỳ nghỉ thoải mái.'',
 N''Khu vực ngủ với rèm che sáng|Bàn trang điểm kết hợp bàn làm việc|Ghế thư giãn|Tủ quần áo và chỗ để hành lý'',
 N''Gương trang điểm|Trà, cà phê trong phòng|Hỗ trợ bàn ủi theo yêu cầu''
),
(
 ''P201'',
 N''Phòng Deluxe với góc ngồi thư giãn và các tiện ích phục vụ công việc, phù hợp khách cần không gian thoải mái.'',
 N''Góc ghế ngồi và bàn trà|Bàn làm việc|Tủ quần áo|Khu vực để hành lý riêng'',
 N''Áo choàng và dép đi trong phòng|Bộ pha trà, cà phê|Minibar có tính phí''
),
(
 ''P202'',
 N''Phòng Deluxe chú trọng ánh sáng tự nhiên và góc làm việc, kết hợp không gian nghỉ ngơi thư thái.'',
 N''Góc làm việc cạnh cửa sổ|Ghế đọc sách|Bàn trang điểm|Rèm che sáng và tủ quần áo'',
 N''Đèn đọc sách tại giường|Ấm đun nước và bộ tách trà|Dịch vụ ăn uống tại phòng có tính phí''
),
(
 ''P301'',
 N''Phòng hướng biển với góc ngồi ngắm cảnh, dành cho khách muốn tận hưởng không khí nghỉ dưỡng bên bờ biển.'',
 N''Khu vực ngủ hướng về cửa kính|Góc ngồi ngắm biển|Ban công theo bố trí phòng|Tủ quần áo và chỗ để hành lý'',
 N''Bàn ghế thư giãn|Bộ pha trà, cà phê|Minibar có tính phí''
),
(
 ''P302'',
 N''Phòng hướng biển kết hợp góc nghỉ ngơi và bàn làm việc, phù hợp vừa nghỉ dưỡng vừa xử lý công việc cá nhân.'',
 N''Góc làm việc có ánh sáng tự nhiên|Ghế thư giãn cạnh cửa kính|Khu vực ngắm biển|Tủ quần áo và bàn trang điểm'',
 N''Đèn đọc sách|Bộ pha trà, cà phê|Két an toàn|Hỗ trợ bàn ủi theo yêu cầu''
),
(
 ''P401'',
 N''Phòng gia đình với góc sinh hoạt chung và bếp nhỏ, thuận tiện cho gia đình có trẻ em lưu trú nhiều ngày.'',
 N''Khu vực ngủ cho gia đình|Sofa sinh hoạt chung|Bàn ăn nhỏ|Bếp nhỏ, tủ lạnh và lò vi sóng'',
 N''Dụng cụ ăn uống cơ bản|Hỗ trợ nôi em bé theo yêu cầu|Khu vực cất hành lý''
),
(
 ''P402'',
 N''Phòng gia đình có khu ngồi thư giãn, góc ăn uống và các tiện ích phục vụ sinh hoạt trong kỳ nghỉ.'',
 N''Khu vực ngủ theo cấu hình giường đã công bố|Góc sofa và bàn trà|Bàn ăn|Tủ lạnh và bếp nhỏ'',
 N''Góc sinh hoạt chung|Dụng cụ ăn uống cơ bản|Hỗ trợ bàn ủi theo yêu cầu''
),
(
 ''P501'',
 N''Phòng Suite có phòng khách riêng để nghỉ ngơi hoặc tiếp khách, kết hợp khu làm việc và phòng tắm thư giãn.'',
 N''Khu vực ngủ riêng|Phòng khách với sofa|Bàn làm việc|Bàn ăn hoặc bàn tiếp khách'',
 N''Bộ pha trà, cà phê|Áo choàng và dép|Dịch vụ ăn uống tại phòng có tính phí''
),
(
 ''P502'',
 N''Phòng Suite chú trọng sự riêng tư với phòng khách, góc đọc sách và không gian thư giãn trong phòng tắm.'',
 N''Khu vực ngủ riêng|Sofa và bàn trà|Góc đọc sách cạnh cửa sổ|Bàn trang điểm và tủ quần áo'',
 N''Góc thư giãn riêng|Bộ pha trà, cà phê|Hỗ trợ bàn ủi theo yêu cầu''
),
(
 ''P601'',
 N''Không gian nghỉ dưỡng cao cấp lấy cảm hứng từ penthouse, có khu tiếp khách và sân hiên để thư giãn riêng tư.'',
 N''Khu vực ngủ theo cấu hình giường đã công bố|Phòng khách và bàn ăn|Bếp nhỏ|Sân hiên với khu ngồi thư giãn'',
 N''Hồ bơi riêng theo cấu hình phòng|Hỗ trợ quản gia theo lịch phục vụ|Ăn uống riêng có tính phí''
),
(
 ''P602'',
 N''Không gian lấy cảm hứng từ villa nghỉ dưỡng, kết hợp khu sinh hoạt gia đình và góc thư giãn ngoài trời.'',
 N''Khu vực ngủ theo cấu hình giường đã công bố|Phòng khách với sofa|Bàn ăn và bếp nhỏ|Khu vực ngồi ngoài trời'',
 N''Hồ bơi riêng theo cấu hình phòng|Hỗ trợ quản gia theo lịch phục vụ|Hỗ trợ bữa ăn riêng theo yêu cầu có tính phí''
)
)v(room_id,mo_ta,khong_gian,tien_ich)
 ON v.room_id=p.room_id;

COMMIT TRANSACTION;
';

COMMIT TRANSACTION;

SELECT
 r.room_id,r.ten_phong,t.ten_loai,t.gia_tien,r.hinh_anh
FROM dbo.Rooms r
LEFT JOIN dbo.Room_Types t ON t.type_id=r.type_id
ORDER BY r.type_id,r.room_id;

SELECT code,discount_percent,kind,enabled
FROM dbo.DiscountCodes;

PRINT N'Đã gộp database gốc và hồ sơ phòng. Dữ liệu hiện có được giữ lại.';

END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
GO